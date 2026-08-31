# frozen_string_literal: true

# A fingerprint of Lago's billing behaviour surface, so that new behaviour is noticed rather than
# waited for.
#
# `rake golden:discover` regenerates this and diffs it against the committed
# spec/scenarios/golden/surface.json. A new enum value, a new route, a new error code, a new
# permitted parameter — or the removal of any of them — becomes a reported delta, which is the
# machinery behind section ③ of the run report.
#
# Everything is sorted, so a diff is a real change rather than a hash-ordering artefact.
module GoldenSurface
  # Models whose constants define billing behaviour. Adding a model here is the one manual step; the
  # constants within it are discovered.
  MODELS = %w[
    AddOn AppliedCoupon BillableMetric Charge ChargeFilter Commitment Coupon CreditNote Customer Fee
    FixedCharge Invoice Plan RecurringTransactionRule Subscription Tax UsageThreshold Wallet
    WalletTransaction
  ].freeze

  # Constants that enumerate values, as opposed to tuning knobs. A flat collection of symbols or
  # strings, or a hash mapping to them.
  def self.enumerating?(value)
    case value
    when Array then value.any? && value.all? { |item| item.is_a?(Symbol) || item.is_a?(String) }
    when Hash then value.any? && value.values.all? { |item| item.is_a?(Symbol) || item.is_a?(String) || item.is_a?(Integer) }
    else false
    end
  end

  def self.normalize(value)
    case value
    when Array then value.map(&:to_s).sort
    when Hash then value.keys.map(&:to_s).sort
    end
  end

  def self.constants
    MODELS.each_with_object({}) do |model_name, out|
      model = model_name.safe_constantize
      next unless model

      model.constants(false).sort.each do |const_name|
        next unless const_name.to_s.match?(/\A[A-Z][A-Z0-9_]*\z/)

        value = begin
          model.const_get(const_name, false)
        rescue
          next
        end
        next unless enumerating?(value)

        out["#{model_name}::#{const_name}"] = normalize(value)
      end
    end
  end

  def self.routes
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      action = route.defaults[:action]
      next if controller.blank? || action.blank?
      next unless controller.start_with?("api/v1/")

      "#{route.verb.to_s.gsub(/[^A-Z]/, "")} #{controller}##{action}"
    end.uniq.sort
  end

  def self.clock_jobs
    Dir[Rails.root.join("app/jobs/clock/*.rb")].map { |path| File.basename(path, ".rb").camelize }.sort
  end

  # Lago's validation messages are identity-mapped, so the leaves under activerecord.errors ARE the
  # error codes clients see. Scoped to that subtree deliberately: the rest of the locale file is date,
  # money and separator formats, which are not behaviour and would churn the diff.
  def self.error_codes
    locale = YAML.safe_load_file(Rails.root.join("config/locales/en.yml"), aliases: true)
    leaves(locale.dig("en", "activerecord", "errors") || {}).uniq.sort
  end

  def self.leaves(value)
    case value
    when Hash then value.values.flat_map { |nested| leaves(nested) }
    when Array then value.flat_map { |nested| leaves(nested) }
    when String then [value]
    else []
    end
  end

  # Approximate by design: permitted params are not introspectable, so these are extracted from the
  # `permit(...)` call sites. A *change* in the set is the signal, so a false positive costs one look.
  def self.permitted_params
    Dir[Rails.root.join("app/controllers/api/v1/**/*_controller.rb")].sort.each_with_object({}) do |path, out|
      source = File.read(path)
      next unless source.include?("permit(")

      keys = source.scan(/permit\(([^)]*(?:\([^)]*\)[^)]*)*)\)/m)
        .flatten.join(",").scan(/:([a-z_][a-z0-9_]*)/).flatten.uniq.sort
      next if keys.empty?

      out[Pathname.new(path).relative_path_from(Rails.root).to_s] = keys
    end
  end

  def self.charge_model_defaults
    Charge::CHARGE_MODELS.to_h do |charge_model|
      properties = ChargeModels::BuildDefaultPropertiesService.call(charge_model)
      [charge_model.to_s, properties.nil? ? nil : properties.keys.map(&:to_s).sort]
    end
  end

  def self.capture
    {
      "constants" => constants,
      "routes" => routes,
      "clock_jobs" => clock_jobs,
      "error_codes" => error_codes,
      "permitted_params" => permitted_params,
      "charge_model_defaults" => charge_model_defaults
    }
  end

  def self.path
    GoldenMatrix.dir.join("surface.json")
  end

  def self.recorded
    return nil unless path.exist?
    JSON.parse(File.read(path)).fetch("surface")
  end

  def self.write!(current = capture)
    path.write(JSON.pretty_generate("captured_at_version" => 1, "surface" => current) + "\n")
    path
  end

  # Deltas grouped by section, each entry naming what appeared or disappeared. Removals matter as
  # much as additions: a rule that stopped existing invalidates the rows that assert it.
  def self.deltas(current = capture, previous = recorded)
    return [{kind: "baseline-missing", detail: "no surface.json recorded yet — run rake golden:surface"}] if previous.nil?

    current.keys.flat_map do |section|
      now = current[section]
      before = previous[section] || (now.is_a?(Hash) ? {} : [])

      if now.is_a?(Hash)
        hash_deltas(section, now, before)
      else
        list_deltas(section, "", now, before)
      end
    end
  end

  def self.hash_deltas(section, now, before)
    added_keys = now.keys - before.keys
    removed_keys = before.keys - now.keys
    shared = now.keys & before.keys

    added_keys.map { |key| {kind: "added", section: section, subject: key, detail: "new: #{Array(now[key]).join(", ")}"} } +
      removed_keys.map { |key| {kind: "removed", section: section, subject: key, detail: "gone"} } +
      shared.flat_map { |key| list_deltas(section, key, Array(now[key]), Array(before[key])) }
  end

  def self.list_deltas(section, subject, now, before)
    (now - before).map { |value| {kind: "added", section: section, subject: subject, detail: value} } +
      (before - now).map { |value| {kind: "removed", section: section, subject: subject, detail: value} }
  end
end
