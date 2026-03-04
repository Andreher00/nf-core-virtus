#!/usr/bin/env python3

# Package import
import pandas as pd
import argparse
from scipy import stats
from statsmodels.stats.multitest import multipletests
import seaborn as sns
import matplotlib as mpl
import matplotlib.pyplot as plt
import pathlib
mpl.rcParams['pdf.fonttype'] = 42
mpl.rcParams['ps.fonttype'] = 42

from scattermap import scattermap

def run_summary(virtus_files, samplesheet_path, th_cov, th_rate, figsize_str):
    # 1. Load Samplesheet to get Groups
    # nf-core samplesheets usually have: sample,fastq_1,fastq_2,group
    samplesheet = pd.read_csv(samplesheet_path)
    
    # 2. Aggregate all VIRTUS output files
    list_df_res = []
    for f in virtus_files:
        # Use pathlib to get the filename without extension (e.g., 'Sample_1')
        sample_name = pathlib.Path(f).stem.split('-')[1]
        d = pd.read_table(f)   
        # Manually inject the name column
        d['name'] = sample_name
        list_df_res.append(d)
    
    df_res = pd.concat(list_df_res)

    # 3. Pivot and Filter (Your original logic)
    th_cov = float(args.th_cov)
    th_rate = float(args.th_rate)

    df_rate = pd.pivot(df_res, index='virus', columns='name', values="rate_hit").fillna(0)
    df_cov = pd.pivot(df_res, index='virus', columns='name', values="coverage").fillna(0)

    df_cov = df_cov[df_cov.max(axis=1) > th_cov]
    df_rate = df_rate[df_rate.max(axis=1) > th_rate]
    
    # Intersection of filters
    list_index = (set(df_rate.index) & set(df_cov.index))
    df_cov = df_cov.reindex(list_index)
    df_rate = df_rate.reindex(list_index)
    
    summary = pd.merge(df_cov, df_rate, left_index=True, right_index=True, suffixes=('_cov', '_rate'))

    # print(summary)

    print("### Stats ###")
    print('Threshold coverage : ', th_cov)
    print('Threshold rate : ', th_rate)

    print('# detected viruses : ', df_res.shape[0])
    print('Max coverage : ', df_res.coverage.max())
    print('Max rate : ', df_res.rate_hit.max())

    print('# retained viruses :', summary.shape[0])

    # 4. Statistical Testing
    if samplesheet['group'].nunique() == 2:
        print("### Conducting Mann-Whitney U-test ###")
        
        # Get the two group names
        group_names = samplesheet['group'].unique()
        group_a_label = group_names[0]
        group_b_label = group_names[1]

        # Filter samplesheet to get lists of sample IDs for each group
        group_a_samples = samplesheet[samplesheet['group'] == group_a_label]['sample'].tolist()
        group_b_samples = samplesheet[samplesheet['group'] == group_b_label]['sample'].tolist()

        # Ensure these samples actually exist in our pivoted results
        # (Sometimes samples fail mapping and won't be in df_rate)
        cols_a = [c for c in group_a_samples if c in df_rate.columns]
        cols_b = [c for c in group_b_samples if c in df_rate.columns]

        u_values = {}
        p_values = {}

        for virus in summary.index:
            # Extract the 'rate_hit' values for this virus across both groups
            data_a = df_rate.loc[virus, cols_a]
            data_b = df_rate.loc[virus, cols_b]

            # Perform the test
            # alternative='two-sided' is standard; use 'greater' if you only care about group A > B
            u, p = stats.mannwhitneyu(data_a, data_b, alternative='two-sided')
            
            u_values[virus] = u
            p_values[virus] = p

        # Convert results to Series for easy merging
        summary["u_stat"] = pd.Series(u_values)
        summary["p_val"] = pd.Series(p_values)

        # 5. Multiple Testing Correction (FDR)
        # Since we are testing hundreds of viruses, we MUST adjust for false discoveries
        if not summary["p_val"].empty:
            # Benjamini-Hochberg (fdr_bh) is the nf-core/genomics standard
            _, fdr, _, _ = multipletests(summary["p_val"], method='fdr_bh')
            summary["FDR"] = fdr
        else:
            summary["FDR"] = np.nan

        print(f"Comparison: {group_a_label} (n={len(cols_a)}) vs {group_b_label} (n={len(cols_b)})")
        print(f"Significant viruses (FDR < 0.05): {sum(summary['FDR'] < 0.05)}")

    # 5. Plotting
    figsize = tuple(map(int, figsize_str.split(',')))
    # Ensure the dataframes are sorted identically so markers match colors
    df_rate = df_rate.sort_index(axis=0).sort_index(axis=1)
    df_cov = df_cov.sort_index(axis=0).sort_index(axis=1)
    with sns.axes_style("white"):
        plt.figure(figsize=figsize)
        # The core scattermap call
        # df_rate determines the color (cmap)
        # marker_size (df_cov) determines how big the dots are
        _ = scattermap(df_rate,
                       square=True,
                       marker_size=df_cov,
                       cmap='viridis_r',
                       cbar_kws={'label': 'v/h rate'}
        )

        #make a legend:
        # Custom Legend Logic for Marker Sizes
        # This creates the "bubbles" on the right explaining what the sizes mean
        pws = [20, 40, 60, 80, 100]
        for pw in pws:
            plt.scatter([], [], s=(pw), c="k",label=str(pw))

        h, l = plt.gca().get_legend_handles_labels()
        plt.legend(h[1:], l[1:],
                   labelspacing=.3,
                   title="coverage(%)",
                   borderpad=0,
                   framealpha=0,
                   edgecolor="w",
                   bbox_to_anchor=(1.1, -.1),
                   ncol=1,
                   loc='upper left',
                   borderaxespad=0
        )
        plt.savefig('scattermap.pdf' , bbox_inches='tight')
        plt.close()
    summary.to_csv("summary.csv")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--inputs', nargs='+', required=True)
    parser.add_argument('--samplesheet', required=True)
    parser.add_argument('--th_cov', default=10)
    parser.add_argument('--th_rate', default=0.0001)
    parser.add_argument('--figsize', default='8,3')
    args = parser.parse_args()
    run_summary(args.inputs, args.samplesheet, args.th_cov, args.th_rate, args.figsize)