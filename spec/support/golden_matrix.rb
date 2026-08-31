# frozen_string_literal: true

# Loads, expands and lints the golden billing matrix.
#
# The matrix is data, not code: `spec/scenarios/golden/matrix/*.yml` holds the rows,
# `spec/scenarios/golden/schema.json` defines their shape, and the lints below cover the rules a
# JSON Schema cannot express. Both runners (the RSpec driver here and dev/golden/live_run.rb) read
# through this module, so a row means the same thing to each of them.
#
# A file may open with a single `__matrix` header element carrying `defaults` and named `groups`.
# Rows join a group with `group:`, name their identifier stem with `key:` and parameterise it with
# `vars:`. Expansion happens HERE, once, before `__file` is stamped, and erases all three authoring
# keys — so schema.json, the lints, the ledger, the findings digests and both runners only ever see
# fully expanded rows and are never told that groups exist.

module GoldenMatrix
  DIR = "spec/scenarios/golden"

  # Fields whose non-zero presence obliges the row to explain its arithmetic in `math`.
  AMOUNT_FIELD = /_cents\z/

  # The reserved key of the optional file header element.
  HEADER_KEY = "__matrix"

  # The only sections a header may declare.
  HEADER_SECTIONS = %w[defaults groups].freeze

  # The only keys a header may supply to a row. Everything else — `expect`, `math`, `pins`, `id`,
  # `axes`, `characterization`, `premium`, `no_transaction` — stays row-local STRUCTURALLY: a header
  # that mentions one is a load error, not a convention someone is trusted to follow. `axes` in
  # particular must never be inheritable, or the ledger's coverage count becomes a claim rather than
  # a measurement.
  INHERITABLE_KEYS = %w[setup timeline dimensions runners provenance].freeze

  # Authoring-only keys. The expander deletes all three, so schema.json's `additionalProperties:
  # false` never sees them and the expanded row stays byte-comparable with the pre-migration one.
  AUTHORING_KEYS = %w[group key vars].freeze

  PLACEHOLDER = /%%\{|%\{([A-Za-z_][A-Za-z0-9_]*)\}/
  WHOLE_PLACEHOLDER = /\A%\{([A-Za-z_][A-Za-z0-9_]*)\}\z/

  # Raised while loading. Everything the expander can get wrong is a typo whose quiet outcome is a
  # row that asserts less than it looks like it asserts, so none of it degrades into a warning.
  MatrixError = Class.new(StandardError)

  class << self
    def dir
      Rails.root.join(DIR)
    end

    def matrix_files
      Dir[dir.join("matrix/*.yml")].sort
    end

    # The one place expansion happens. Everything downstream — schema validation, the lints, the
    # census, GoldenLedger, GoldenFindings, GoldenRunner, the rake tasks — reads rows through here,
    # so no caller can reach an unexpanded row and mistake a group's inherited timeline for a
    # missing one.
    def rows
      matrix_files.flat_map do |file|
        source = relative_path(file)
        expand_file(load_document(file), source, []).each do |row|
          row["__file"] = source
          # Invoices::PreviewService prices charges in Parallel worker threads, each drawing its own
          # pool connection. Under the :transaction cleaning strategy only the connection holding the
          # open transaction can see the row's data, so what a preview returns is a per-thread draw
          # (F101). Previewing rows therefore always run on committed data.
          row["no_transaction"] = true if Array(row["timeline"]).any? { |step| step["do"] == "preview_invoice" }
        end
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
      errors.concat(authoring_lint_errors)
      errors.concat(duplicate_id_errors)
      rows.each do |row|
        errors.concat(row_lint_errors(row))
      end
      errors
    end

    # Lints on the AUTHORING layer, which the schema cannot see because expansion erases it. Read
    # from the files rather than from `rows`, so they still fire when a caller stubs `rows`.
    def authoring_lint_errors
      matrix_files.flat_map do |file|
        source = relative_path(file)
        lints = []
        expanded = expand_file(load_document(file), source, lints)
        if expanded.empty?
          lints << "#{source}: contributes no rows. A file whose rows all vanished still leaves a " \
                   "green suite, so nothing else would say its coverage is gone."
        end
        lints
      end
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

    def relative_path(file)
      Pathname.new(file).relative_path_from(Rails.root).to_s
    end

    def load_document(file)
      YAML.safe_load_file(file, permitted_classes: [], aliases: true) || []
    end

    # The key order schema.json lists row properties in. Merged rows are rebuilt in it so key order
    # is a pure function of WHICH keys a row has, never of the order its author happened to type
    # them or of which layer supplied them.
    def canonical_row_keys
      @canonical_row_keys ||= JSON.parse(File.read(dir.join("schema.json")))
        .dig("definitions", "row", "properties").keys
    end

    # A file with no header and no row carrying an authoring key is returned untouched — the same
    # Hash objects YAML produced, in the same order, with the same keys. That identity is what lets
    # the 21 files convert one at a time against a frozen baseline.
    def expand_file(document, source, lints)
      unless document.is_a?(Array)
        raise MatrixError, "#{source}: the document must be a sequence of rows, got #{type_name(document)}"
      end

      header, body = split_header(document, source)
      return body if header.nil? && body.none? { |row| authored?(row) }

      defaults = validated_section(header&.dig("defaults"), "#{HEADER_KEY}.defaults", source)
      groups = validated_groups(header&.dig("groups"), source)

      body.map { |row| expand_row(row, defaults, groups, source, lints) }
    end

    def authored?(row)
      row.is_a?(Hash) && AUTHORING_KEYS.any? { |key| row.key?(key) }
    end

    def split_header(document, source)
      positions = document.each_index.select do |index|
        document[index].is_a?(Hash) && document[index].key?(HEADER_KEY)
      end
      return [nil, document] if positions.empty?

      unless positions == [0]
        raise MatrixError, "#{source}: the #{HEADER_KEY} header must be the FIRST element and there " \
                           "may be only one; found #{positions.size} at element(s) #{positions.inspect}"
      end

      element = document.first
      unless element.keys == [HEADER_KEY]
        raise MatrixError, "#{source}: #{HEADER_KEY} must be the only key of the header element, " \
                           "alongside #{(element.keys - [HEADER_KEY]).inspect}. A row and a header " \
                           "cannot share an element."
      end

      header = element[HEADER_KEY] || {}
      raise MatrixError, "#{source}: #{HEADER_KEY} must be a mapping, got #{type_name(header)}" unless header.is_a?(Hash)

      extra = header.keys - HEADER_SECTIONS
      if extra.any?
        raise MatrixError, "#{source}: #{HEADER_KEY} takes only #{HEADER_SECTIONS.join(" and ")}; got #{extra.inspect}"
      end

      [header, document.drop(1)]
    end

    # A header section may supply only the five inheritable keys. `expect` in `defaults` would hand
    # assertions to rows that declared none — two hundred rows passing while asserting nothing — so
    # it is refused here rather than discouraged in prose.
    def validated_section(section, label, source)
      return {} if section.nil?
      raise MatrixError, "#{source}: #{label} must be a mapping, got #{type_name(section)}" unless section.is_a?(Hash)

      extra = section.keys - INHERITABLE_KEYS
      return section if extra.none?

      raise MatrixError, "#{source}: #{label} may only supply #{INHERITABLE_KEYS.join(", ")}; " \
                         "#{extra.inspect} is row-local and cannot be inherited"
    end

    def validated_groups(groups, source)
      return {} if groups.nil?
      unless groups.is_a?(Hash)
        raise MatrixError, "#{source}: #{HEADER_KEY}.groups must be a mapping of name => section, got #{type_name(groups)}"
      end

      groups.to_h { |name, section| [name, validated_section(section, "#{HEADER_KEY}.groups.#{name}", source)] }
    end

    def expand_row(row, defaults, groups, source, lints)
      raise MatrixError, "#{source}: every element after the header must be a row mapping" unless row.is_a?(Hash)

      where = "#{source} #{row["id"] || "(row with no id)"}"
      group = named_group(row, groups, where)

      inherited = deep_merge(deep_merge(defaults, group, where), row.slice(*INHERITABLE_KEYS), where)
      merged = row.except(*AUTHORING_KEYS, *INHERITABLE_KEYS).merge(inherited)

      canonical(substitute_row(merged, row, where, lints))
    end

    def named_group(row, groups, where)
      name = row["group"]
      return {} if name.nil?

      groups.fetch(name) do
        raise MatrixError, "#{where}: group #{name.inspect} is not declared in this file's " \
                           "#{HEADER_KEY} header (declared: #{groups.keys.inspect}). An unknown group " \
                           "merges nothing, which silently strips the row of everything it meant to inherit."
      end
    end

    # Precedence, lowest to highest: file defaults, the one named group, the row. Hashes merge
    # key-wise; ARRAYS REPLACE, always — an index-wise merge of `timeline` would rewrite steps
    # rather than override them, and would look like it worked.
    def deep_merge(base, override, where, path = nil)
      override.each_with_object(base.dup) do |(key, value), result|
        full = [path, key].compact.join(".")

        if value.nil?
          tombstone!(result, key, full, where)
        elsif result[key].is_a?(Hash) && value.is_a?(Hash)
          result[key] = deep_merge(result[key], value, where, full)
        elsif result.key?(key) && !result[key].nil? && kind(result[key]) != kind(value)
          raise MatrixError, "#{where}: #{full} is #{type_name(result[key])} in a lower layer and " \
                             "#{type_name(value)} here. A change of shape between layers is a typo, not an override."
        else
          result[key] = value
        end
      end
    end

    # `~` is the opt-out, and an opt-out that removes nothing is either a typo or a null someone
    # meant as a VALUE — `dimensions: {regroup_paid_fees: ~}` reads exactly like both. Refusing it
    # keeps the two apart instead of resolving them in silence.
    def tombstone!(result, key, full, where)
      unless result.key?(key)
        raise MatrixError, "#{where}: #{full}: ~ deletes nothing — no lower layer supplies #{full}. " \
                           "Null is reserved as the inheritance opt-out; it cannot carry a value here."
      end

      result.delete(key)
    end

    def kind(value)
      case value
      when Hash then :mapping
      when Array then :sequence
      else :scalar
      end
    end

    def type_name(value)
      case value
      when Hash then "a mapping"
      when Array then "a sequence"
      when NilClass then "null"
      else "a #{value.class.name.downcase}"
      end
    end

    # One pass, after the merge, over every string VALUE of the merged row. It deliberately reaches
    # `expect` and `timeline`: `key` and `vars` live in the row, so a row's assertions stay its own
    # even when its setup and timeline came from a group.
    def substitute_row(merged, row, where, lints)
      vars = declared_vars(row, where)
      consumed = []
      substituted = substitute(merged, vars, where, consumed)

      unused = vars.keys - consumed.uniq
      if unused.any?
        lints << "#{where}: declares #{unused.inspect} which no %{...} placeholder uses. The " \
                 "group's own value shipped instead of the one this row meant to supply."
      end

      substituted
    end

    def declared_vars(row, where)
      declared = row["vars"] || {}
      raise MatrixError, "#{where}: `vars` must be a mapping, got #{type_name(declared)}" unless declared.is_a?(Hash)

      if declared.key?("key")
        raise MatrixError, "#{where}: `vars` cannot redefine `key`; the identifier stem is the row's own `key:`"
      end

      return declared unless row.key?("key")

      declared.merge("key" => row["key"])
    end

    def substitute(value, vars, where, consumed)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), out|
          if key.is_a?(String) && key.include?("%{")
            raise MatrixError, "#{where}: placeholder in the key #{key.inspect}; substitution applies to values only"
          end
          out[key] = substitute(nested, vars, where, consumed)
        end
      when Array
        value.map { |nested| substitute(nested, vars, where, consumed) }
      when String
        substitute_string(value, vars, where, consumed)
      else
        value
      end
    end

    # Two forms. A value that is EXACTLY "%{name}" becomes the var's raw YAML value, type intact —
    # that is what lets a group timeline take `amount: "%{e1}"` and receive the integer 40 rather
    # than the string "40", which would reach the events API as a string and change the arithmetic.
    # A placeholder among other characters interpolates and yields a String.
    def substitute_string(string, vars, where, consumed)
      return string unless string.include?("%{")

      if string.gsub(PLACEHOLDER, "").include?("%{")
        raise MatrixError, "#{where}: malformed placeholder in #{string.inspect} — %{...} must name " \
                           "a var matching [A-Za-z_][A-Za-z0-9_]*, and a literal %{ is written %%{"
      end

      whole = string.match(WHOLE_PLACEHOLDER)
      if whole
        consumed << whole[1]
        return fetch_var(vars, whole[1], where, string)
      end

      string.gsub(PLACEHOLDER) do |match|
        next "%{" if match == "%%{"

        name = Regexp.last_match(1)
        consumed << name
        interpolated(fetch_var(vars, name, where, string), name, where, string)
      end
    end

    def interpolated(value, name, where, string)
      return value.to_s unless value.is_a?(Hash) || value.is_a?(Array)

      raise MatrixError, "#{where}: %{#{name}} in #{string.inspect} is #{type_name(value)}; only " \
                         "scalars interpolate. Use it as the whole value to keep its type."
    end

    # An unresolved placeholder must never survive as a literal: `aggregation_type: "%{agg}"` would
    # create a metric whose aggregation is the string "%{agg}", and the row would then be measured
    # against whatever that produced.
    def fetch_var(vars, name, where, string)
      vars.fetch(name) do
        raise MatrixError, "#{where}: unresolved %{#{name}} in #{string.inspect}; declared vars are " \
                           "#{vars.keys.inspect}"
      end
    end

    def canonical(row)
      ordered = canonical_row_keys.each_with_object({}) { |key, out| out[key] = row[key] if row.key?(key) }
      row.except(*canonical_row_keys).each { |key, value| ordered[key] = value }
      ordered
    end

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
