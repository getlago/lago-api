# frozen_string_literal: true

# Triage state for what the suite knows is wrong. A row's `pins:` says a finding is guarded and
# `characterization: true` says a row asserts what Lago DOES rather than what its `math` derives;
# neither says whether a human has looked. `findings.yml` is the list someone has read, and this
# module compares the two against it so a run reports what is NEW.
#
#   untracked   a characterization row with no `pins:` — a defect recorded with nothing to track it by
#   unacknowledged  a pinned finding with no ledger entry
#   changed     a ledger entry whose rows' assertions moved. Either it was partly fixed or it got
#               worse; silently re-accepting the new numbers is how a characterization row becomes a
#               rubber stamp
#   resolved    an entry no row pins any more — fixed, or the row was deleted
module GoldenFindings
  module_function

  LEDGER = "spec/scenarios/golden/findings.yml"

  def ledger_path
    Rails.root.join(LEDGER)
  end

  # Characterization rows carrying no finding id: the defect is written down only inside the row that
  # happens to assert it.
  def untracked(rows: GoldenMatrix.rows)
    rows.select { |row| row["characterization"] && Array(row["pins"]).empty? }
      .map { |row| {"id" => row["id"], "block" => row["block"], "summary" => summary(row)} }
      .sort_by { |finding| finding["id"] }
  end

  def observed(rows: GoldenMatrix.rows)
    GoldenLedger.pinned_findings(rows:).map do |finding_id, row_ids|
      pinning = rows.select { |row| row_ids.include?(row["id"]) }
      {
        "id" => finding_id,
        "rows" => row_ids.sort,
        "digest" => digest(pinning),
        "summary" => pinning.filter_map { |row| summary(row) if row["characterization"] }.first
      }
    end.sort_by { |finding| finding["id"] }
  end

  # Over the assertions of every row pinning the finding, so rewording `math` is free and moving a
  # number is not.
  def digest(pinning_rows)
    material = pinning_rows.sort_by { |row| row["id"] }.map { |row| [row["id"], row["expect"]] }

    Digest::SHA256.hexdigest(material.to_s)[0, 12]
  end

  # A hint for whoever triages. Self-applied labels are stripped: rows use them inconsistently.
  def summary(row)
    text = row["math"].to_s.squish.sub(/\A(REPORTED BUG[^.]*\.|CHARACTERIZATION[^.]*\.)\s*/i, "")
    return nil if text.empty?

    (text.length > 160) ? "#{text[0, 157]}..." : text
  end

  def acknowledged
    return [] unless File.exist?(ledger_path)

    YAML.safe_load_file(ledger_path, permitted_classes: [], aliases: true) || []
  end

  SEVERITY_ORDER = %w[MONEY BROKEN API HARNESS-CRITICAL HARNESS DOC PROCESS UNRESOLVED].freeze

  # The dated markdown log, regenerated from the ledger rather than appended to by hand — which is how
  # it drifted from the matrix in the first place. Pinning is resolved live from rows' `pins:`, so the
  # log always states what actually holds each finding still today.
  def to_markdown(rows: GoldenMatrix.rows, on: Time.zone.today)
    pinned = GoldenLedger.pinned_findings(rows:)
    entries = acknowledged.reject { |entry| entry["status"] == "withdrawn" }
    live, closed = entries.partition { |entry| entry["status"] != "resolved" }

    [
      markdown_header(on, live, pinned),
      *live.sort_by { |entry| [SEVERITY_ORDER.index(entry["severity"]) || 99, entry["id"]] }
        .map { |entry| markdown_entry(entry, pinned) },
      closed.any? ? "\n---\n\n## Resolved\n" : nil,
      *closed.map { |entry| markdown_entry(entry, pinned) }
    ].compact.join("\n")
  end

  def markdown_header(on, live, pinned)
    by_severity = live.group_by { |entry| entry["severity"] }
      .transform_values(&:size)
      .sort_by { |severity, _| SEVERITY_ORDER.index(severity) || 99 }
      .map { |severity, count| "#{severity} #{count}" }
      .join(" · ")
    unpinned = live.count { |entry| pinned[entry["id"]].blank? }

    <<~HEADER
      # Golden suite — findings log

      Generated #{on} by `rake golden:findings:export` from `spec/scenarios/golden/findings.yml`.
      **Edit the ledger, not this file** — anything written here is overwritten by the next run.

      #{live.size} open · #{by_severity}
      #{live.size - unpinned} pinned by a row · **#{unpinned} not pinned**

      A finding nothing pins is prose: the next refactor moves the behaviour and nobody is told.
      Pinning is resolved live from rows' `pins:`, so the counts above are today's, not when the
      finding was written.

      ---
    HEADER
  end

  def markdown_entry(entry, pinned)
    rows = pinned[entry["id"]]
    pin_line = if rows.present?
      "PINNED by #{rows.sort.join(", ")}"
    else
      "NOT PINNED — nothing fails if this behaviour changes."
    end
    ticket = entry["ticket"].present? ? " (#{entry["ticket"]})" : ""

    "\n## #{entry["id"]} [#{entry["severity"]}] #{entry["title"]}#{ticket}\n" \
      "#{entry["body"]}\n#{pin_line}\n"
  end

  def unacknowledged(rows: GoldenMatrix.rows)
    known = acknowledged.map { |entry| entry["id"] }

    observed(rows:).reject { |finding| known.include?(finding["id"]) }
  end

  def changed(rows: GoldenMatrix.rows)
    known = acknowledged.index_by { |entry| entry["id"] }

    observed(rows:).filter_map do |finding|
      entry = known[finding["id"]]
      next if entry.nil? || entry["digest"] == finding["digest"]

      finding.merge("was" => entry["digest"])
    end
  end

  def resolved(rows: GoldenMatrix.rows)
    present = observed(rows:).map { |finding| finding["id"] }

    acknowledged.reject { |entry| present.include?(entry["id"]) }
  end

  # Refreshes the digest of every pinned finding IN PLACE. Never rewrites the ledger: the finding
  # bodies live there and are the only copy — the dated markdown is generated from them, not the
  # other way round.
  def refresh_digests!(rows: GoldenMatrix.rows)
    current = observed(rows:).index_by { |finding| finding["id"] }
    updated = []

    entries = acknowledged.map do |entry|
      finding = current[entry["id"]]
      next entry if finding.nil? || entry["digest"] == finding["digest"]

      updated << entry["id"]
      entry.merge("digest" => finding["digest"])
    end

    write_ledger(entries)
    updated
  end

  # Rewrites the file preserving the comment header, since that is where the format is documented.
  def write_ledger(entries)
    header = ledger_path.read.split(/^---$/, 2).first
    ledger_path.write("#{header}---\n#{entries.to_yaml.delete_prefix("---\n")}")
  end
end
