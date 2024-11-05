# frozen_string_literal: true

class ApiKeyMailerPreview < BasePreviewMailer
  def rotated
    api_key = FactoryBot.create(:api_key)
    ApiKeyMailer.with(api_key:).rotated
  end
end
