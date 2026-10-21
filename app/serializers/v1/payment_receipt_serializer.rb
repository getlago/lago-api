# frozen_string_literal: true

module V1
  class PaymentReceiptSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        number: model.reload.number,
        file_url: model.file_url,
        file_url_expires_at: model.file_url_expires_at&.iso8601,
        xml_url: model.xml_url,
        xml_url_expires_at: model.xml_url_expires_at&.iso8601,
        payment: payment,
        created_at: model.created_at.iso8601
      }
    end

    private

    def payment
      ::V1::PaymentSerializer.new(model.payment).serialize
    end
  end
end
