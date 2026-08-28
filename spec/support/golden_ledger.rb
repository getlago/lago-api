# frozen_string_literal: true

# The coverage ledger: what the golden matrix claims, what is legal, and what is missing.
#
# Coverage is computed per block against that block's own axis product. Legal cells come from
# GoldenLegality, which reads the model constants, so the denominator grows on its own when Lago
# gains a charge model, an aggregation or an interval.
#
# Nothing here shells out to git or touches the network; RISK is computed separately by
# lib/tasks/golden.rake so that the specs stay deterministic and offline.
module GoldenLedger
  module_function

  def blocks
    YAML.safe_load_file(GoldenMatrix.dir.join("blocks.yml"), aliases: true)
  end

  def block(id)
    blocks.find { |b| b["id"] == id } or raise ArgumentError, "unknown golden block #{id.inspect}"
  end

  def axis_values(spec)
    return GoldenLegality.domain(spec["domain"]).map(&:to_s) if spec.key?("domain")

    spec.fetch("values").map(&:to_s)
  end

  # Every combination of the block's axes that Lago permits AND the REST API can express. The two
  # filters are deliberately distinct: `constraint` is model legality (verified against real
  # validation by legality_spec.rb), `api_reachable?` is a property of the API surface.
  def legal_cells(block)
    candidate_cells(block).select { |cell| GoldenLegality.api_reachable?(cell.symbolize_keys) }
  end

  # Of the legal cells, those the HARNESS can currently say: a cell whose block or axis value declares
  # a `requires:` the interpreter does not satisfy cannot be written today, however legal it is.
  # Reported separately so the blocked work stays visible rather than being quietly subtracted.
  def expressible_cells(block)
    schema = GoldenCapabilities.golden_schema
    legal_cells(block).select { |cell| unmet_requirements(block, cell, schema).empty? }
  end

  def unmet_requirements(block, cell, schema = GoldenCapabilities.golden_schema)
    requirements_for(block, cell).reject do |kind, value|
      GoldenCapabilities.satisfied?(kind, value, schema: schema)
    end
  end

  # Block-level `requires:` applies to every cell; a `requires:` under an axis applies only to cells
  # holding that axis value.
  def requirements_for(block, cell)
    collected = (block["requires"] || {}).to_a

    block["axes"].each do |name, spec|
      per_value = spec["requires"] or next
      needed = per_value[cell[name]] or next
      collected.concat(needed.to_a)
    end

    collected.uniq
  end

  # Why each blocked cell is blocked, grouped so the ledger can print one line per reason rather
  # than one per cell.
  def blocked_reasons(block)
    schema = GoldenCapabilities.golden_schema
    (legal_cells(block) - expressible_cells(block))
      .flat_map { |cell| unmet_requirements(block, cell, schema).map { |kind, value| "#{kind}:#{value}" } }
      .tally
  end

  # Model-legal cells, before the API-reachability filter.
  def candidate_cells(block)
    names = block["axes"].keys
    domains = names.map { |name| axis_values(block["axes"][name]) }
    fixed = (block["fixed"] || {}).transform_values(&:to_s)
    constraint = block["constraint"] || "none"

    domains.first.product(*domains.drop(1)).filter_map do |combo|
      cell = names.zip(Array(combo)).to_h
      next unless GoldenLegality.constraint(constraint, cell.merge(fixed).symbolize_keys)
      cell
    end
  end

  def api_unreachable_cells(block)
    candidate_cells(block) - legal_cells(block)
  end

  def rows_for(block_id, rows: GoldenMatrix.rows)
    rows.select { |row| row["block"] == block_id }
  end

  # A row claims a cell by naming every axis of its block; a partial naming is malformed, not a claim.
  def declared_cells(block, rows: GoldenMatrix.rows)
    names = block["axes"].keys
    rows_for(block["id"], rows:).filter_map do |row|
      axes = (row["axes"] || {}).transform_values(&:to_s)
      next unless names.all? { |name| axes.key?(name) }
      axes.slice(*names)
    end.uniq
  end

  def malformed_rows(block, rows: GoldenMatrix.rows)
    names = block["axes"].keys
    rows_for(block["id"], rows:).filter_map do |row|
      axes = (row["axes"] || {}).keys
      missing = names - axes
      extra = axes - names
      next if missing.empty? && extra.empty?
      {id: row["id"], missing: missing, extra: extra}
    end
  end

  # Cells a row claims that Lago does not permit: the signal that a validation rule changed under the
  # matrix, rather than that the matrix is merely incomplete.
  def illegal_declared_cells(block, rows: GoldenMatrix.rows)
    declared_cells(block, rows:) - legal_cells(block)
  end

  def missing_cells(block, rows: GoldenMatrix.rows)
    legal_cells(block) - declared_cells(block, rows:)
  end

  def summary(rows: GoldenMatrix.rows)
    blocks.map do |block|
      legal = legal_cells(block)
      expressible = expressible_cells(block)
      declared = declared_cells(block, rows:) & legal
      {
        id: block["id"],
        title: block["title"],
        rows: rows_for(block["id"], rows:).size,
        legal: legal.size,
        covered: declared.size,
        percent: legal.empty? ? 0 : (declared.size * 100.0 / legal.size).round,
        expressible: expressible.size,
        # Percent of what can actually be written today — the number that should drive effort.
        expressible_percent: expressible.empty? ? 0 : ((declared & expressible).size * 100.0 / expressible.size).round,
        blocked: legal.size - expressible.size,
        blocked_reasons: blocked_reasons(block),
        api_unreachable: api_unreachable_cells(block).size,
        missing: expressible - declared,
        illegal: illegal_declared_cells(block, rows:),
        malformed: malformed_rows(block, rows:),
        services: block["services"] || []
      }
    end
  end

  def totals(rows: GoldenMatrix.rows)
    all = summary(rows:)
    legal = all.sum { |b| b[:legal] }
    expressible = all.sum { |b| b[:expressible] }
    covered = all.sum { |b| b[:covered] }
    {
      blocks: all.size,
      rows: rows.size,
      legal: legal,
      expressible: expressible,
      blocked: legal - expressible,
      covered: covered,
      percent: legal.zero? ? 0 : (covered * 100.0 / legal).round,
      expressible_percent: expressible.zero? ? 0 : (covered * 100.0 / expressible).round
    }
  end

  # ------------------------------------------------------------------ scenario inventory

  # What is covered TODAY, row by row: the cell each row claims, the context it pins, what it asserts,
  # and the arithmetic it stands on. schema.json is the CONTRACT a row must satisfy; this is the
  # census of the rows that exist, generated rather than hand-edited.
  def scenarios(rows: GoldenMatrix.rows)
    titles = blocks.to_h { |block| [block["id"], block["title"]] }

    rows.sort_by { |row| row["id"] }.map do |row|
      expectation = row["expect"] || {}
      {
        "id" => row["id"],
        "block" => row["block"],
        "block_title" => titles[row["block"]],
        "cell" => row["axes"],
        "pinned" => row["dimensions"] || {},
        "asserts" => expectation.keys.sort,
        "assert_fields" => scenario_assert_fields(expectation),
        "steps" => (row["timeline"] || []).map { |step| step["do"] },
        "provenance" => row["provenance"],
        "runners" => row["runners"],
        "flags" => %w[premium characterization calendar_sensitive needs_forward_time no_transaction]
          .select { |flag| row[flag] },
        "math" => row["math"] || row["note"],
        "file" => row["__file"]
      }
    end
  end

  # The leaf field names a row actually asserts — the difference between "it checks an invoice" and
  # "it checks the invoice total, tax and two fees".
  def scenario_assert_fields(expectation)
    expectation.flat_map do |kind, value|
      case value
      when Hash then value.keys.reject { |key| key == "select" }.map { |key| "#{kind}.#{key}" }
      else [kind]
      end
    end.sort
  end

  # How a row is recognised as having looked at an invoice that was not finalized. A draft, a preview
  # and a finalized invoice are three different computations of the same period, so a block whose rows
  # only ever read a finalized one is blind to a third of its own behaviour. Reported rather than
  # turned into an axis on every block, where most cells would be ones draft and final provably agree on.
  SURFACE_MARKERS = {
    draft: ->(row) { row.to_s.include?("status: draft") || row.to_s.include?('"draft"') },
    regenerated: ->(row) { row.to_s.include?("refresh_invoice") || row.to_s.include?("perform_invoices_refresh") },
    preview: ->(row) { row.to_s.include?("preview_invoice") }
  }.freeze

  def surface_coverage(rows: GoldenMatrix.rows)
    rows.group_by { |row| row["block"] }.transform_values do |block_rows|
      dumped = block_rows.map(&:to_s)
      SURFACE_MARKERS.transform_values { |probe| dumped.count { |row| probe.call(row) } }
    end.sort_by { |block, _| [block[/\d+/].to_i, block] }.to_h
  end

  # Blocks that have never asserted anything but a finalized invoice — counting B21, which covers other
  # blocks' surfaces on their behalf. A block named as a B21 `subject_block` is not blind: its surfaces
  # are asserted, just from the cross-cutting block rather than from its own file.
  def surface_blind_blocks(rows: GoldenMatrix.rows)
    delegated = rows.filter_map { |row| row.dig("axes", "subject_block") }.uniq

    surface_coverage(rows:)
      .except(*delegated)
      .select { |_block, counts| counts.values.sum.zero? }
      .keys
  end

  # Every axis naming a surface must draw from one vocabulary, or cross-block surface coverage is
  # unanswerable.
  SURFACE_AXIS_NAMES = %w[observed_via surface].freeze

  def surface_vocabulary_errors(blocks: GoldenLedger.blocks)
    allowed = GoldenLegality::SURFACE_VOCABULARY + GoldenLegality::NON_SURFACE_AXIS_VALUES
    blocks.flat_map do |block|
      (block["axes"] || {}).filter_map do |name, spec|
        next unless SURFACE_AXIS_NAMES.include?(name)
        stray = axis_values(spec) - allowed
        next if stray.empty?
        "#{block["id"]} axis #{name} uses #{stray.inspect}, which is not in " \
          "GoldenLegality::SURFACE_VOCABULARY #{allowed.inspect}"
      end
    end
  end

  def pinned_findings(rows: GoldenMatrix.rows)
    rows.each_with_object({}) do |row, out|
      Array(row["pins"]).each { |id| (out[id] ||= []) << row["id"] }
    end
  end

  def findings_summary(rows: GoldenMatrix.rows)
    pinned = pinned_findings(rows: rows)
    {pinned: pinned, pinned_count: pinned.keys.size, rows_pinning: pinned.values.sum(&:size)}
  end

  # Cells guarded by specs outside the golden suite, keyed by block. Weaker than a golden row — no
  # derived math, no exact-value discipline — so they never count as covered; they only stop the map
  # reporting a gap somebody is already watching.
  def external_coverage
    path = GoldenMatrix.dir.join("external_coverage.yml")
    return {} unless path.exist?

    YAML.safe_load_file(path, aliases: true).each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |entry, acc|
      acc[entry.fetch("block")][entry.fetch("cell").transform_values(&:to_s)] = entry.fetch("covered_by")
    end
  end

  # Every writeable cell of a block, marked with the row that covers it or nil — the whole combination
  # space with coverage attached, not a sample of what is missing.
  def cell_map(block, rows: GoldenMatrix.rows)
    names = block["axes"].keys
    claims = rows_for(block["id"], rows:).each_with_object({}) do |row, acc|
      axes = (row["axes"] || {}).transform_values(&:to_s)
      next unless names.all? { |name| axes.key?(name) }
      acc[axes.slice(*names)] = row["id"]
    end

    external = external_coverage[block["id"]] || {}
    expressible_cells(block).map do |cell|
      cell.merge("covered_by" => claims[cell], "external" => external[cell])
    end
  end

  def scenario_summary(rows: GoldenMatrix.rows)
    all = scenarios(rows:)
    {
      "generated_from_rows" => all.size,
      "blocks" => summary(rows:).map do |block|
        definition = block_by_id(block[:id])
        {
          "id" => block[:id], "title" => block[:title],
          "covered" => block[:covered], "writeable" => block[:expressible],
          "axes" => definition["axes"].keys,
          "cells" => cell_map(definition, rows:)
        }
      end,
      "scenarios" => all
    }
  end

  def block_by_id(id)
    blocks.find { |block| block["id"] == id }
  end

  # ------------------------------------------------------------------ actions

  def action_scope
    YAML.safe_load_file(GoldenMatrix.dir.join("actions.yml"), aliases: true)
  end

  MUTATING_VERBS = %w[POST PUT PATCH DELETE].freeze

  # Read from Rails' own route table rather than by parsing config/routes.rb, so a new endpoint
  # cannot be missed by a regex.
  def all_mutating_actions
    Rails.application.routes.routes.filter_map do |route|
      verb = route.verb.to_s.gsub(/[^A-Z]/, "")
      next unless MUTATING_VERBS.include?(verb)

      controller = route.defaults[:controller]
      action = route.defaults[:action]
      next if controller.blank? || action.blank?

      {controller: controller, action: action, verb: verb, path: route.path.spec.to_s.sub("(.:format)", "")}
    end.uniq { |entry| "#{entry[:controller]}##{entry[:action]}" }
  end

  def in_scope_actions
    scope = action_scope
    included = scope.fetch("include")
    excluded = scope["exclude_actions"] || []

    all_mutating_actions.reject do |entry|
      key = "#{entry[:controller]}##{entry[:action]}"
      !included.include?(entry[:controller]) || excluded.include?(key)
    end
  end

  # An action is covered when some row's timeline reaches it: each step verb maps onto the endpoint it
  # calls.
  STEP_ACTIONS = {
    "create_subscription" => ["api/v1/subscriptions#create"],
    "terminate_subscription" => ["api/v1/subscriptions#terminate"],
    "ingest_events" => ["api/v1/events#create"],
    "pay_fees" => ["api/v1/fees#update"],
    "pay_invoice" => ["api/v1/payments#create"],
    "create_credit_note" => ["api/v1/credit_notes#create"],
    "update_plan_charge" => ["api/v1/plans/charges#update"],
    "fetch_current_usage" => [],
    "refresh_invoice" => ["api/v1/invoices#refresh"],
    "finalize_invoice" => ["api/v1/invoices#finalize"],
    "void_invoice" => ["api/v1/invoices#void"]
  }.freeze

  SETUP_ACTIONS = {
    "metrics" => ["api/v1/billable_metrics#create"],
    "plan" => ["api/v1/plans#create"],
    "customer" => ["api/v1/customers#create"],
    "taxes" => ["api/v1/taxes#create"],
    "coupons" => ["api/v1/coupons#create", "api/v1/applied_coupons#create"],
    "wallets" => ["api/v1/wallets#create"]
  }.freeze

  def covered_actions(rows: GoldenMatrix.rows)
    rows.flat_map do |row|
      from_setup = (row["setup"] || {}).keys.flat_map { |key| SETUP_ACTIONS.fetch(key, []) }
      from_steps = (row["timeline"] || []).flat_map { |step| STEP_ACTIONS.fetch(step["do"], []) }
      from_setup + from_steps
    end.uniq
  end

  def action_summary(rows: GoldenMatrix.rows)
    in_scope = in_scope_actions.map { |entry| "#{entry[:controller]}##{entry[:action]}" }
    covered = covered_actions(rows:) & in_scope
    {
      total: in_scope.size,
      covered: covered.size,
      percent: in_scope.empty? ? 0 : (covered.size * 100.0 / in_scope.size).round,
      missing: (in_scope - covered).sort,
      out_of_scope: (all_mutating_actions.map { |e| "#{e[:controller]}##{e[:action]}" } - in_scope).size
    }
  end
end
