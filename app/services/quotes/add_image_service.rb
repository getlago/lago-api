# frozen_string_literal: true

module Quotes
  class AddImageService < BaseService
    include OrderForms::Premium

    Result = BaseResult[:image_url]

    def initialize(quote:, image:)
      @quote = quote
      @image = image

      super
    end

    def call
      return result.not_found_failure!(resource: "quote") unless quote
      return result.forbidden_failure! unless order_forms_enabled?(quote.organization)

      attachment = image_attachment
      return result if result.failure?

      quote.images.attach(attachment)
      quote.save!

      result.image_url = Rails.application.routes.url_helpers.rails_blob_url(
        quote.images.attachments.last.blob,
        host: ENV["LAGO_API_URL"]
      )
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :quote, :image

    def image_attachment
      decoded = Utils::Base64File.decode(image)

      if decoded.nil?
        result.single_validation_failure!(field: :image, error_code: "invalid_format")
        return
      end

      {
        io: decoded.io,
        filename: filename(decoded.content_type),
        content_type: decoded.content_type
      }
    end

    def filename(content_type)
      "quote-image-#{SecureRandom.uuid}.#{content_type.split("/").last}"
    end
  end
end
