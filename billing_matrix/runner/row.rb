# frozen_string_literal: true

require "yaml"
require "time"
require "date"
require "bigdecimal"

require_relative "errors"
require_relative "timeline"
require_relative "world"

module BillingMatrix
  class Row
    KEYS = %w[id area axes setup timeline expect math control canary pins single_event_is_the_point].freeze
    REQUIRED = %w[id area timeline expect].freeze
    ID_FORMAT = %r{\A[a-z0-9_-]+(/[a-z0-9_.+-]+)+\z}
    PIN_FORMAT = /\A[A-Z]+-?\d+\z/
    EXPECT_KEY = /\A(invoices|invoice|invoice\[[1-9]\d*\]|wallet|credit_note|subscription|preview|error)\z/
    INVOICE_LIKE_KEY = /\A(invoice|invoice\[\d+\]|preview)\z/
    INVOICE_KEYS = %w[
      invoice_type status fees_amount_cents coupons_amount_cents prepaid_credit_amount_cents
      progressive_billing_credit_amount_cents credit_notes_amount_cents sub_total_excluding_taxes_amount_cents
      taxes_amount_cents total_amount_cents fees_count fees
    ].freeze
    INTERACTION_KEYS = %w[
      coupons_amount_cents prepaid_credit_amount_cents progressive_billing_credit_amount_cents
      credit_notes_amount_cents taxes_amount_cents
    ].freeze

    attr_reader :id, :area, :axes, :setup, :timeline, :expect, :math, :control, :canary, :pins, :source

    # Resolve every input before validating references: a control can live in another path.
    def self.load_all(paths)
      files = Array(paths).flat_map do |path|
        matches = File.file?(path) ? [path] : Dir.glob(File.join(path, "**", "*.yml")).sort
        raise InvalidRow, "no *.yml row files at #{path}" if matches.empty?

        matches
      end
      rows = files.flat_map { |path| load_file(path) }
      reject_duplicate_ids!(rows)
      check_controls!(rows)
      rows
    end

    def self.load_file(path)
      documents = YAML.safe_load_file(path, permitted_classes: [Time, Date], aliases: true, filename: path)
      unless documents.is_a?(Array)
        raise InvalidRow, "#{path}: expected a top-level list of rows, got #{documents.class}"
      end

      documents.map { |hash| new(hash, source: path).validate! }
    rescue Psych::SyntaxError => e
      raise InvalidRow, "#{path}: YAML syntax error: #{e.message}"
    end

    def self.reject_duplicate_ids!(rows)
      rows.group_by(&:id).each_value do |same_id|
        next if same_id.size == 1

        first, second = same_id
        second.invalid!("id", "duplicates row #{first.id.inspect} from #{first.source}")
      end
    end

    def self.check_controls!(rows)
      ids = rows.map(&:id)
      rows.each do |row|
        next if row.control.nil? || ids.include?(row.control)

        row.invalid!("control", "names #{row.control.inspect}, which is not a loaded row")
      end
    end

    def initialize(hash, source:)
      @raw = hash
      @source = source
      return unless hash.is_a?(Hash)

      @id = hash["id"]
      @area = hash["area"]
      @axes = hash["axes"] || {}
      @setup = hash["setup"] || {}
      @timeline = hash["timeline"] || []
      @expect = hash["expect"] || {}
      @math = hash["math"]
      @control = hash["control"]
      @canary = hash["canary"]
      @pins = hash["pins"] || []
    end

    def canary? = !canary.nil?

    def single_event_is_the_point? = @raw.is_a?(Hash) && @raw["single_event_is_the_point"] == true

    def validate!
      invalid!("row", "must be a mapping, got #{@raw.class}") unless @raw.is_a?(Hash)
      if @raw.key?("__matrix")
        invalid!("__matrix", "templating headers are not supported; write each row out in full")
      end

      check_required_keys!
      check_unknown_keys!(@raw, KEYS, "row")
      if @raw.key?("single_event_is_the_point") && ![true, false].include?(@raw["single_event_is_the_point"])
        invalid!("single_event_is_the_point", "must be true or false")
      end
      check_id!
      check_axes!
      check_setup!
      check_timeline!
      check_expect!
      check_math!
      check_control!
      check_canary!
      check_pins!
      check_error_coupling!
      check_single_event!
      self
    end

    def invalid!(field, message)
      raise InvalidRow, "row #{id.inspect} (#{source}) #{field}: #{message}"
    end

    private

    def check_required_keys!
      REQUIRED.each do |key|
        value = @raw[key]
        invalid!(key, "is required") if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end

    def check_unknown_keys!(hash, known, field)
      unknown = hash.keys.map(&:to_s) - known
      return if unknown.empty?

      invalid!(field, "unknown key(s) #{unknown.inspect}; known: #{known.inspect}")
    end

    def check_id!
      invalid!("id", "must be a String") unless id.is_a?(String)
      invalid!("id", "must look like area/axis-value/axis-value, got #{id.inspect}") unless id.match?(ID_FORMAT)
      invalid!("area", "must be a String") unless area.is_a?(String)
      invalid!("id", "must start with the area (#{area.inspect}/)") unless id.start_with?("#{area}/")
    end

    def check_axes!
      invalid!("axes", "must be a mapping of axis => value") unless axes.is_a?(Hash)
      axes.each do |axis, value|
        next if value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false

        invalid!("axes.#{axis}", "must be a scalar, got #{value.class}")
      end
      @axes = axes.to_h { |axis, value| [axis.to_s, value.to_s] }
    end

    def check_setup!
      invalid!("setup", "must be a mapping") unless setup.is_a?(Hash)

      begin
        World.validate!(setup)
      rescue InvalidRow => e
        invalid!("setup", e.message)
      end
    end

    def check_timeline!
      invalid!("timeline", "must be a non-empty list of steps") unless timeline.is_a?(Array) && timeline.any?

      previous = nil
      @timeline = timeline.each_with_index.map do |step, index|
        field = "timeline[#{index + 1}]"
        invalid!(field, "must be a mapping with `at` and `do`") unless step.is_a?(Hash)
        at = parse_at(step["at"], field)
        invalid!("#{field}.at", "#{at.iso8601} is earlier than the previous step") if previous && at < previous
        previous = at
        check_step!(step, field)
        step.merge("at" => at.utc.iso8601)
      end
    end

    def parse_at(value, field)
      case value
      when Time then value
      when DateTime then value.to_time
      when Date then Time.utc(value.year, value.month, value.day)
      when String then Time.iso8601(value)
      else invalid!("#{field}.at", "is required and must be an ISO8601 instant")
      end
    rescue ArgumentError
      invalid!("#{field}.at", "#{value.inspect} is not an ISO8601 instant")
    end

    def check_step!(step, field)
      verb = step["do"]
      unless Timeline.verbs.include?(verb)
        invalid!("#{field}.do", "unknown verb #{verb.inspect}; Timeline implements: #{Timeline.verbs.join(", ")}")
      end
      allowed = Timeline.step_keys(verb)
      check_unknown_keys!(step, allowed, field) if allowed
      Timeline.required_step_keys(verb).each do |key|
        invalid!("#{field}.#{key}", "is required for #{verb}") if step[key].nil?
      end
      if Timeline.needs_body?(verb) && Timeline.body(step).empty?
        invalid!(field, "#{verb} carries no parameters, so the step would do nothing")
      end
      if step.key?("fails")
        invalid!("#{field}.fails", "must be true when present") unless step["fails"] == true
        invalid!("#{field}.fails", "is not supported for #{verb}") unless Timeline.failable?(verb)
      end
      check_step_events!(step, field) if verb == "ingest_events"
    end

    def check_step_events!(step, field)
      events = step["events"]
      invalid!("#{field}.events", "must be a non-empty list") unless events.is_a?(Array) && events.any?

      events.each_with_index do |event, index|
        event_field = "#{field}.events[#{index + 1}]"
        invalid!(event_field, "must be a mapping") unless event.is_a?(Hash)
        check_unknown_keys!(event, Timeline::EVENT_KEYS, event_field)
        count = event.fetch("count", 1)
        invalid!("#{event_field}.count", "must be a positive integer") unless count.is_a?(Integer) && count >= 1
        invalid!("#{event_field}.properties", "must be a mapping") if event.key?("properties") && !event["properties"].is_a?(Hash)
      end
    end

    def check_expect!
      invalid!("expect", "must be a non-empty mapping") unless expect.is_a?(Hash) && expect.any?

      expect.each do |key, value|
        invalid!("expect.#{key}", "unknown expectation; supported: invoices, invoice, invoice[N], wallet, credit_note, subscription, preview, error") unless key.to_s.match?(EXPECT_KEY)

        if key == "invoices"
          invalid!("expect.invoices", "must be a non-negative integer count") unless value.is_a?(Integer) && value >= 0
        else
          invalid!("expect.#{key}", "must be a non-empty mapping of fields") unless value.is_a?(Hash) && value.any?
          check_invoice_fields!(value, "expect.#{key}") if key.to_s.match?(INVOICE_LIKE_KEY)
        end
      end
    end

    def check_invoice_fields!(fields, field)
      check_unknown_keys!(fields, INVOICE_KEYS, field)
      return unless fields.key?("fees")

      fees = fields["fees"]
      invalid!("#{field}.fees", "must be a list of fee mappings") unless fees.is_a?(Array) && fees.all?(Hash)
      if fields.key?("fees_count") && fields["fees_count"] != fees.size
        invalid!("#{field}.fees_count", "is #{fields["fees_count"]} but `fees` lists #{fees.size}")
      end
    end

    def check_math!
      return unless nonzero_cents?(expect)
      return if math.is_a?(String) && !math.strip.empty?

      invalid!("math", "is required because `expect` asserts a non-zero *_cents amount; say how the number was derived")
    end

    def nonzero_cents?(value)
      case value
      when Hash
        value.any? do |key, nested|
          (key.to_s.end_with?("_cents") && nested.is_a?(Numeric) && nested != 0) || nonzero_cents?(nested)
        end
      when Array then value.any? { |nested| nonzero_cents?(nested) }
      else false
      end
    end

    def check_control!
      if control.nil?
        return unless asserts_interaction?

        invalid!("control", "is required: `expect` asserts two reducers on one invoice " \
                            "(#{interacting_keys.inspect}), so the row must name the control row proving each reducer alone")
      end
      invalid!("control", "must be another row's id") unless control.is_a?(String) && control.match?(ID_FORMAT)
      invalid!("control", "cannot be the row itself") if control == id
    end

    def asserts_interaction? = interacting_keys.any?

    def interacting_keys
      expect.select { |key, _| key.to_s.match?(INVOICE_LIKE_KEY) }.each_value.flat_map do |fields|
        next [] unless fields.is_a?(Hash)

        present = INTERACTION_KEYS.select { |key| fields[key].is_a?(Numeric) && fields[key] != 0 }
        (present.size >= 2) ? present : []
      end
    end

    def check_canary!
      return if canary.nil?
      return if canary.is_a?(Hash) && canary.any?

      invalid!("canary", "must be a non-empty mapping saying which mechanism the canary guards")
    end

    def check_pins!
      invalid!("pins", "must be a list of finding ids such as F69 or BIL-537") unless pins.is_a?(Array)
      pins.each do |pin|
        next if pin.is_a?(String) && pin.match?(PIN_FORMAT)

        invalid!("pins", "#{pin.inspect} is not a finding id such as F69 or BIL-537")
      end
      invalid!("pins", "a canary cannot pin a finding") if canary? && pins.any?
    end

    def check_error_coupling!
      failing = timeline.select { |step| step["fails"] == true }
      if expect.key?("error") && failing.size != 1
        invalid!("expect.error", "needs exactly one timeline step marked `fails: true`; found #{failing.size}")
      end
      if failing.any? && !expect.key?("error")
        invalid!("timeline", "has a step marked `fails: true` but `expect` has no `error`, so the rejection would go unasserted")
      end
    end

    def check_single_event!
      ingest_steps = timeline.select { |step| step["do"] == "ingest_events" }
      total = ingest_steps.sum { |step| step["events"].sum { |event| event.fetch("count", 1) } }
      lone = ingest_steps.size == 1 && total == 1

      if lone && !single_event_is_the_point?
        invalid!("timeline", "has exactly one ingest_events step carrying one event; one event cannot distinguish " \
                             "per-event pricing from a cumulative delta. Add a second event, or set " \
                             "`single_event_is_the_point: true` if one event genuinely is the point")
      elsif single_event_is_the_point? && !lone
        invalid!("single_event_is_the_point", "is set but the timeline has #{ingest_steps.size} ingest_events step(s) " \
                                              "totalling #{total} event(s); the opt-in is vacuous")
      end
    end
  end
end
