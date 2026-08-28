# frozen_string_literal: true

# Loads and lints the golden billing matrix.
#
# The matrix is data, not code: `spec/scenarios/golden/matrix/*.yml` holds the rows,
# `spec/scenarios/golden/schema.json` defines their shape, and the lints below cover the rules a
# JSON Schema cannot express. Both runners (the RSpec driver here and dev/golden/live_run.rb) read
# through this module, so a row means the same thing to each of them.
module GoldenMatrix
  DIR = "spec/scenarios/golden"

  # Fields whose non-zero presence obliges the row to explain its arithmetic in `math`.
  AMOUNT_FIELD = /_cents\z/

  class << self
    def dir
      Rails.root.join(DIR)
    end

    def matrix_files
      Dir[dir.join("matrix/*.yml")].sort
    end

    def rows
      matrix_files.flat_map do |file|
        loaded = YAML.safe_load_file(file, permitted_classes: [], aliases: true) || []
        loaded.each { |row| row["__file"] = Pathname.new(file).relative_path_from(Rails.root).to_s }
      end
    end

    def schema
      JSONSchemer.schema(JSON.parse(File.read(dir.join("schema.json"))))
    end

    # Schema violations, reported per row so a failure names the offending file and id.
    def schema_errors
      compiled = schema
      rows.map do |row|
        candidate = row.except("__file")
        errors = compiled.validate([candidate]).map do |error|
          "#{error["data_pointer"].presence || "(root)"}: #{error["type"]}"
        end
        next if errors.empty?
        "#{row["__file"]} #{row["id"] || "(row with no id)"}\n    #{errors.uniq.join("\n    ")}"
      end.compact
    end

    # Rules the schema cannot express.
    def lint_errors
      errors = []
      errors.concat(duplicate_id_errors)
      rows.each do |row|
        errors.concat(row_lint_errors(row))
      end
      errors
    end

    def census
      rows.group_by { |row| row["block"] }.transform_values do |block_rows|
        {
          rows: block_rows.size,
          cells: block_rows.map { |row| row["axes"] }.uniq.size,
          live: block_rows.count { |row| row["runners"].include?("live") },
          characterization: block_rows.count { |row| row["characterization"] }
        }
      end.sort.to_h
    end

    private

    def duplicate_id_errors
      rows.group_by { |row| row["id"] }
        .select { |_id, group| group.size > 1 }
        .map { |id, group| "duplicate row id #{id.inspect} in #{group.map { |r| r["__file"] }.uniq.join(", ")}" }
    end

    def row_lint_errors(row)
      errors = []
      id = "#{row["__file"]} #{row["id"]}"

      # The id must name its own block, so a row can be located from a failure line alone. Ids are
      # zero-padded (b01) so files and examples sort naturally, while blocks are not (B1).
      id_block = row["id"].to_s[%r{\Ab(\d+)/}, 1]
      row_block = row["block"].to_s[/\AB(\d+)\z/, 1]
      if id_block.nil? || row_block.nil? || id_block.to_i != row_block.to_i
        errors << "#{id}: id must start with \"b#{row_block || "<n>"}/\" (zero-padding optional) to match block #{row["block"].inspect}"
      end

      # YAML 1.1 turns bare `on`, `off`, `yes`, `no`, `y`, `n` keys into booleans, which then silently
      # fail to match any field name. Catching it generically beats rediscovering it per field.
      golden_non_string_keys(row).each do |key|
        errors << "#{id}: key #{key.inspect} parsed as #{key.class} — quote it, or rename it (YAML 1.1 " \
                  "reads on/off/yes/no/y/n as booleans)"
      end

      if expects_non_zero_amount?(row) && row["math"].blank?
        errors << "#{id}: expects a non-zero amount but has no `math` line explaining how it is derived"
      end

      # A row that cannot be shifted onto the current clock cannot honestly claim the live runner.
      if row["runners"].include?("live") && (row["calendar_sensitive"] || row["needs_forward_time"])
        reason = row["calendar_sensitive"] ? "calendar_sensitive" : "needs_forward_time"
        errors << "#{id}: is #{reason} so it cannot run live; drop \"live\" from runners"
      end

      has_timeline = row["timeline"].present?
      if has_timeline == row.key?("at")
        errors << "#{id}: needs exactly one of `at` (setup is the whole action) or `timeline`"
      end

      if row["expect"].key?("error") && row["expect"].keys.size > 1
        errors << "#{id}: expect.error is terminal — it cannot be combined with #{(row["expect"].keys - ["error"]).inspect}"
      end

      # Probe rows observe behaviour while investigating. Left behind they become permanent
      # "coverage" that nobody derived and nobody reviewed.
      if row["id"].to_s.include?("/probe/")
        errors << "#{id}: probe rows are for investigation only and must be deleted before finishing"
      end

      errors.concat(axes_agree_with_setup_errors(row, id))
      errors.concat(multi_invoice_selector_errors(row, id))
      errors.concat(block_file_errors(row, id))

      charge_codes = (row.dig("setup", "charges") || []).map { |c| c["billable_metric_code"] }
      metric_codes = (row.dig("setup", "metrics") || []).map { |c| c["code"] }
      (charge_codes - metric_codes).uniq.each do |missing|
        errors << "#{id}: charge references metric #{missing.inspect} which the row does not declare"
      end

      errors
    end

    # A row claims a coverage cell by declaring `axes`. Unchecked, it could declare
    # {charge_model: volume, aggregation: max_agg} over a standard/sum_agg setup, pass, and move the
    # coverage number, making the denominator a label rather than a measurement.
    def axes_agree_with_setup_errors(row, id)
      axes = row["axes"] || {}
      errors = []

      declared = axes["charge_model"]
      actual = (row.dig("setup", "charges") || []).map { |charge| charge["charge_model"] }.compact.uniq
      if declared && actual.any? && !actual.include?(declared.to_s)
        errors << "#{id}: axes.charge_model is #{declared.inspect} but setup declares #{actual.inspect}"
      end

      declared = axes["aggregation"]
      actual = (row.dig("setup", "metrics") || []).map { |metric| metric["aggregation_type"] }.compact.uniq
      if declared && actual.any? && !actual.include?(declared.to_s)
        errors << "#{id}: axes.aggregation is #{declared.inspect} but setup declares #{actual.inspect}"
      end

      errors
    end

    # Rows are found by opening the file their block names, so one filed under another block's file is
    # invisible to whoever maintains that block. The id already has to match `block`; so must the FILE.
    def block_file_errors(row, id)
      file_block = File.basename(row["__file"].to_s)[/\Ab(\d+)_/, 1]
      row_block = row["block"].to_s[/\AB(\d+)\z/, 1]
      return [] if file_block.nil? || row_block.nil?
      return [] if file_block.to_i == row_block.to_i

      ["#{id}: is a #{row["block"]} row but lives in a B#{file_block.to_i} file — move it, or the " \
       "block's own file no longer shows all of its rows"]
    end

    # Two entries with the same (or no) selector resolve to the same invoice, so the second asserts
    # nothing while looking like it covers the other side of the interaction.
    def multi_invoice_selector_errors(row, id)
      expectations = row.dig("expect", "invoice")
      return [] unless expectations.is_a?(Array)

      selectors = expectations.map { |expected| expected["select"] }
      return ["#{id}: every invoice in a multi-invoice expectation needs its own `select`"] if selectors.any?(&:blank?)

      duplicates = selectors.tally.select { |_selector, count| count > 1 }.keys
      return [] if duplicates.empty?

      ["#{id}: invoice selector(s) #{duplicates.inspect} appear twice — both resolve to the same " \
       "invoice, so one of the two expectations asserts nothing"]
    end

    def golden_non_string_keys(value)
      case value
      when Hash
        value.keys.reject { |key| key.is_a?(String) } +
          value.values.flat_map { |nested| golden_non_string_keys(nested) }
      when Array
        value.flat_map { |nested| golden_non_string_keys(nested) }
      else
        []
      end
    end

    def expects_non_zero_amount?(row)
      invoices = Array.wrap(row.dig("expect", "invoice"))
      amounts = invoices.flat_map { |invoice| amount_values(invoice) + (invoice["fees"] || []).flat_map { |fee| amount_values(fee) } }
      usage_amounts = amount_values(row.dig("expect", "usage") || {})

      (amounts + usage_amounts).any? { |value| value.to_i != 0 }
    end

    def amount_values(fields)
      fields.select { |field, _| field.match?(AMOUNT_FIELD) }.values
    end
  end
end
