# frozen_string_literal: true

module SettingsStorable
  extend ActiveSupport::Concern

  class_methods do
    def settings_accessors(*method_names, default: nil)
      method_names.each do |name|
        define_method(name) do
          value = get_from_settings(name.to_s)
          value.nil? ? default : value
        end

        define_method(:"#{name}=") do |value|
          push_to_settings(key: name.to_s, value:)
        end
      end
    end
  end

  def push_to_settings(key:, value:)
    self.settings ||= {}
    settings[key] = value
  end

  def get_from_settings(key)
    (settings || {})[key]
  end
end
