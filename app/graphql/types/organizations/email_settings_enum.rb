# frozen_string_literal: true

module Types
  module Organizations
    class EmailSettingsEnum < Types::BaseEnum
      Organization::EMAIL_SETTINGS.each do |code|
        value code.tr('.', '_'), code
      end
    end
  end
end
