# frozen_string_literal: true

# Parses EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) output into the fields the
# summaries and the scoreboard use. Plain Ruby, shared by explain.rb and
# summarize.rb.
module PaymentsFiltersPerf
  module PlanStats
    WATCHED_TABLES = %w[payments invoices payment_receipts].freeze

    module_function

    # nil when the statement timed out.
    def execution_ms(plan)
      plan[/Execution Time: ([\d.]+) ms/, 1]&.to_f
    end

    def analyse(plan)
      top = plan.lines.first.to_s
      sort_rows = plan.scan(/(?:->\s+|^\s*)(?:Incremental )?Sort\s.*?actual time=[\d.]+\.\.[\d.]+ rows=(\d+)/).flatten.map(&:to_i)
      seq_scans = plan.scan(/Seq Scan on (\w+)/).flatten.uniq & WATCHED_TABLES
      buffers = plan[/Buffers: shared hit=(\d+)(?: read=(\d+))?/]
      hit, read = buffers ? [Regexp.last_match(1).to_i, Regexp.last_match(2).to_i] : [nil, nil]
      {
        ms: execution_ms(plan)&.round(1),
        timeout: plan.start_with?("TIMEOUT"),
        rows_returned: top[/rows=(\d+) loops/, 1].to_i,
        rows_scanned: plan.scan(/actual time=[\d.]+\.\.[\d.]+ rows=(\d+) loops=(\d+)/).sum { |r, l| r.to_i * l.to_i },
        nodes: plan.scan(/->\s+([A-Z][A-Za-z ]+?)(?:\s+on|\s+using|\s+\(|$)/).flatten.map(&:strip).uniq,
        seq_scan_watched: seq_scans,
        sort_rows_max: sort_rows.max || 0,
        shared_hit: hit,
        shared_read: read,
        cursor_index: plan.include?("index_payments_by_cursor"),
        sort_on_created_at: plan.match?(/Sort Key: payments\.created_at/)
      }
    end

    # Flags used in summaries: SLOW (> 200 ms list), COUNT>500, SEQ:<tables>, SORT>10k, TIMEOUT.
    def flags(list, count)
      flags = []
      flags << "SLOW" if list[:timeout] || (list[:ms] && list[:ms] > 200.0)
      flags << "COUNT>500" if count[:timeout] || (count[:ms] && count[:ms] > 500.0)
      seq = (list[:seq_scan_watched] + count[:seq_scan_watched]).uniq
      flags << "SEQ:#{seq.join(",")}" if seq.any?
      flags << "SORT>10k" if list[:sort_rows_max] > 10_000
      flags << "TIMEOUT" if list[:timeout] || count[:timeout]
      flags
    end

    def summary_markdown(phase, entries, runs:, variants: false)
      md = "# Plans: #{phase}\n\n"
      md << "Median of #{runs} EXPLAIN (ANALYZE, BUFFERS) runs per statement. Synthetic dataset. `ms` is nil when the statement hit the timeout.\n\n"
      extra_head = variants ? " count capped ms | count no-visibility ms |" : ""
      md << "| case | page | selective | list ms | count ms |#{extra_head} rows | list nodes | seq scan (watched) | max sort rows | shared read (list) | ordering by cursor index | flags |\n"
      md << "|---|---|---|---|---|#{"---|---|" if variants}---|---|---|---|---|---|---|\n"
      entries.each do |e|
        seq = (e[:list][:seq_scan_watched] + e[:count][:seq_scan_watched]).uniq.join(", ")
        extra = variants ? " #{e.dig(:count_capped, :ms)} | #{e.dig(:count_no_visibility, :ms)} |" : ""
        md << "| #{e[:name]} | #{e[:page]} | #{e[:selective]} | #{e[:list][:ms] || "timeout"} | #{e[:count][:ms] || "timeout"} |#{extra} #{e[:list][:rows_returned]} " \
              "| #{e[:list][:nodes].join(", ")} | #{seq} | #{e[:list][:sort_rows_max]} | #{e[:list][:shared_read]} | #{e[:list][:cursor_index] && !e[:list][:sort_on_created_at]} | #{e[:flags].join(" ")} |\n"
      end
      md
    end
  end
end
