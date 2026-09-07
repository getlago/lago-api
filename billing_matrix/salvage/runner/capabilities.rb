# frozen_string_literal: true

# What the harness can express, DERIVED from the interpreter rather than declared: every list here is
# read out of GoldenRunner's own source, so it cannot disagree with the code it describes. A
# hand-written manifest could let schema.json promise a capability the runner never implements, and
# rows using it would pass while asserting nothing.
#
# Two consumers:
#   * spec/scenarios/golden/harness_spec.rb — asserts schema.json and the runner agree, in BOTH
#     directions, so neither can gain a capability the other lacks.
#   * GoldenLedger — subtracts cells the harness cannot express, so RISK ranks work that can
#     actually be done rather than pointing at walls.
module GoldenCapabilities
  module_function

  SOURCE = "spec/support/golden_runner.rb"

  def source
    File.read(Rails.root.join(SOURCE))
  end

  # The `when "..."` labels of perform_golden_step: the timeline verbs the interpreter dispatches.
  def step_verbs
    section = source[/def perform_golden_step.*?\n  end/m] or
      raise "GoldenCapabilities: perform_golden_step not found in #{SOURCE} — the derivation broke"

    section.scan(/when "([a-z_]+)"/).flatten.uniq.sort
  end

  # Stages of setup at which a row may expect a rejection.
  def error_stages
    GoldenRunner::SUPPORTED_ERROR_STAGES.map(&:to_s).sort
  end

  # The `kind` values golden_resource can read back.
  def resource_kinds
    section = source[/def golden_resource.*?\n  end/m] or
      raise "GoldenCapabilities: golden_resource not found in #{SOURCE} — the derivation broke"

    section.scan(/when "([a-z_]+)"/).flatten.uniq.sort
  end

  # Top-level `expect:` keys the assertion phase actually reads.
  def expectation_kinds
    section = source[/def assert_golden_expectations.*?\n  end/m] or
      raise "GoldenCapabilities: assert_golden_expectations not found in #{SOURCE} — the derivation broke"

    (section.scan(/expectation\["([a-z_]+)"\]/).flatten + section.scan(/expectation\.key\?\("([a-z_]+)"\)/).flatten)
      .push("error") # handled during setup rather than in the assertion phase
      .uniq.sort
  end

  # Setup sections the interpreter materialises. Scanned across the whole file, because
  # materialise_golden_setup threads `setup` into the helpers that do the reading.
  def setup_keys
    (source.scan(/setup\["([a-z_]+)"\]/).flatten + %w[subscription]).uniq.sort
  end

  # Where each setup section is materialised, so nested keys can be scanned PER SECTION: over the whole
  # file a literal belonging to one section satisfies another by accident, and the unread key survives.
  # A map of WHERE to look, never of what is supported — a method renamed away raises rather than
  # reporting its section as satisfied.
  SETUP_SECTION_SOURCES = {
    "organization" => %w[apply_golden_organization],
    "taxes" => %w[create_golden_tax],
    "add_ons" => %w[create_golden_add_on],
    "metrics" => %w[create_golden_metric],
    "plan" => %w[create_golden_plan golden_currency],
    "plans" => %w[create_golden_extra_plan create_golden_plan golden_currency],
    "charges" => %w[golden_charge_params],
    "customer" => %w[create_golden_customer golden_customer_params],
    "subscription" => %w[golden_create_subscription golden_apply_termination_policy],
    "coupons" => %w[apply_golden_coupon],
    "wallets" => %w[create_golden_wallet],
    "fixed_charges" => %w[create_golden_fixed_charge]
  }.freeze

  def method_source(name)
    source[/^  def #{Regexp.escape(name)}\b.*?\n  end$/m] or
      raise "GoldenCapabilities: #{name} not found in #{SOURCE} — the derivation broke"
  end

  # Nested keys of one setup section that the interpreter demonstrably reads, or `:wholesale` when the
  # section's entry hash is handed to the API as-is and every key it declares therefore reaches the
  # request by construction.
  def setup_section_keys(section)
    names = SETUP_SECTION_SOURCES.fetch(section) do
      raise ArgumentError, "GoldenCapabilities: no source region declared for setup section #{section.inspect}"
    end
    region = with_referenced_constants(names.map { |name| method_source(name) }.join("\n"))

    return :wholesale if wholesale_forward?(region)

    key_literals(region)
  end

  # Both spellings a key takes in the runner: `charge["min_amount_cents"]` and the `%w[...]`
  # whitelists it iterates over, which carry no quotes at all.
  def key_literals(region)
    quoted = region.scan(/"([a-z_][a-z_0-9]*)"/).flatten
    word_arrays = region.scan(/%w\[([^\]]*)\]/m).flatten.flat_map(&:split)

    (quoted + word_arrays).uniq.sort
  end

  # A whitelist may live in a constant rather than inline (FLAT_CUSTOMER_KEYS, TERMINATION_POLICY_KEYS).
  def with_referenced_constants(region)
    definitions = region.scan(/\b([A-Z][A-Z0-9_]+)\b/).flatten.uniq
      .filter_map { |name| source[/^  #{name} = .*?\.freeze/m] }

    ([region] + definitions).join("\n")
  end

  # `<var>.symbolize_keys` forwards the section's own hash when `<var>` is the method's PARAMETER; a
  # local assigned inside the body is a whitelist that merely ends in symbolize_keys, as in
  # apply_golden_organization's `permitted.symbolize_keys`.
  def wholesale_forward?(region)
    region.scan(/(?:^|[\s=(])([a-z_][a-z_0-9]*)(?:\.except\([^)]*\))?\.symbolize_keys/)
      .flatten
      .any? { |identifier| !region.match?(/^\s*#{Regexp.escape(identifier)} =[^=]/) }
  end

  # Every nested key schema.json declares that the interpreter never reads — the bug class the
  # top-level setup_keys check cannot see.
  def unread_setup_keys(schema = golden_schema)
    (schema.dig("definitions", "setup", "properties") || {}).flat_map do |section, definition|
      declared = nested_schema_keys(definition)
      next [] if declared.empty?

      read = setup_section_keys(section)
      next [] if read == :wholesale

      (declared - read).map { |key| "#{section}.#{key}" }
    end.sort
  end

  def nested_schema_keys(definition)
    properties = definition["properties"] || definition.dig("items", "properties") || {}
    properties.keys
  end

  # Can a row express this requirement today? Requirements are declared per block or per axis value in
  # blocks.yml and checked here:
  #   step:        a timeline verb the interpreter dispatches
  #   expectation: a top-level `expect:` key the assertion phase reads
  #   schema:      a dotted path that must exist in schema.json, i.e. somewhere for a row to SAY it
  REQUIREMENT_KINDS = %w[step expectation schema].freeze

  def satisfied?(kind, value, schema: nil)
    case kind
    when "step" then step_verbs.include?(value)
    when "expectation" then expectation_kinds.include?(value)
    when "schema" then schema_path?(schema || golden_schema, value)
    else raise ArgumentError, "unknown golden requirement kind #{kind.inspect} (known: #{REQUIREMENT_KINDS.join(", ")})"
    end
  end

  def golden_schema
    JSON.parse(File.read(GoldenMatrix.dir.join("schema.json")))
  end

  def schema_path?(schema, dotted)
    !schema.dig("definitions", *dotted.split(".")).nil?
  end

  def all
    {
      "step_verbs" => step_verbs,
      "error_stages" => error_stages,
      "resource_kinds" => resource_kinds,
      "expectation_kinds" => expectation_kinds,
      "setup_keys" => setup_keys
    }
  end
end
