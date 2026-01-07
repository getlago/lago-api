# frozen_string_literal: true

class FeatureFlag
  DEFINITION = begin
    yaml = YAML.parse_file(Rails.root.join("app/config/feature_flags.yaml"))
    yaml.presence&.to_ruby || {} # Handle empty yaml file
  end.with_indifferent_access.freeze

  class << self
    def enabled?(feature_name, organization:)
      ensure_feature_flag_exists!(feature_name)
      Flipper.enabled?(feature_name, organization)
    end

    def disabled?(feature_name, organization:)
      !enabled?(feature_name, organization:)
    end

    def enable(feature_name, organization:)
      ensure_feature_flag_exists!(feature_name)
      Flipper.enable(feature_name, organization)
    end

    def disable(feature_name, organization:)
      ensure_feature_flag_exists!(feature_name)
      Flipper.disable(feature_name, organization)
    end

    def sanitize!
      found = Flipper.features.map(&:key)
      defined = DEFINITION.keys

      (found - defined).each { |name| Flipper.remove(name) }
      (defined - found).each { |name| Flipper.add(name) }
      self
    end

    private

    def ensure_feature_flag_exists!(name)
      return if Rails.env.production?

      raise "Unknown feature flag: #{name}" unless DEFINITION.key?(name)
    end
  end
end
