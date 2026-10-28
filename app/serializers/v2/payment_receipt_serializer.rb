# frozen_string_literal: true

module V2
  class PaymentReceiptSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        number: model.number,
        lago_payment_id: model.payment_id,
        pdf_url: model.file_url,
        pdf_url_expires_at: format_time(model.file_url_expires_at),
        xml_url: model.xml_url,
        xml_url_expires_at: format_time(model.xml_url_expires_at),
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at)
      }
    end
  end
end
