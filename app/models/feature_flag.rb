# frozen_string_literal: true

class FeatureFlag
  FEATURES = {
    feature1: {
      description: 'Feature 1 description',
    },
  }.with_indifferent_access.freeze

  class << self
    def enabled?(feature_name, actor: nil)
      ensure_feature_flag_exists!(feature_name)
      Flipper.enabled?(feature_name, actor)
    end

    def disabled?(feature_name, actor: nil)
      !enabled?(feature_name, actor:)
    end

    def enable(feature_name, actor: nil)
      ensure_feature_flag_exists!(feature_name)
      Flipper.enable(feature_name, actor)
    end

    def disable(feature_name, actor: nil)
      ensure_feature_flag_exists!(feature_name)
      Flipper.disable(feature_name, actor)
    end

    def sync!
      found = Flipper.features.inject([]) { |memo, feature| memo << feature.key.to_sym }
      defined = FEATURES.keys

      (found - defined).each { |name| Flipper.remove(name) }
      (defined - found).each { |name| Flipper.add(name) }
    end

    private

    def ensure_feature_flag_exists!(name)
      return if Rails.env.production?

      raise "Unknown feature flag: #{name}" unless FEATURES.key?(name)
    end
  end
end
