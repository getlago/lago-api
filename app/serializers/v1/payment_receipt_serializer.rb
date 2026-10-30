# frozen_string_literal: true

module V1
  class PaymentReceiptSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        number:,
        file_url: model.file_url,
        file_url_expires_at: model.file_url_expires_at&.iso8601,
        xml_url: model.xml_url,
        xml_url_expires_at: model.xml_url_expires_at&.iso8601,
        payment: payment,
        created_at: model.created_at.iso8601
      }
    end

    private

    # NOTE: The number is set by a database trigger on insert, so a new receipt has none in memory.
    #       Fetch only that column to keep the preloaded associations.
    def number
      model.number || PaymentReceipt.where(id: model.id).pick(:number)
    end

    def payment
      ::V1::PaymentSerializer.new(model.payment).serialize
    end
  end
end
