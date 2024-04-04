# frozen_string_literal: true

module SettingsStorable
  extend ActiveSupport::Concern

  def push_to_settings(key:, value:)
    self.settings ||= {}
    settings[key] = value
  end

  def get_from_settings(key)
    (settings || {})[key]
  end
end
