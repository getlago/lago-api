# frozen_string_literal: true

module V2
  class PaymentReceiptSerializer < ModelSerializer
    timestamps :pdf_url_expires_at, :xml_url_expires_at, :created_at, :updated_at

    def serialize
      {
        lago_id: model.id,
        number: model.number,
        lago_payment_id: model.payment_id,
        pdf_url: model.file_url,
        xml_url: model.xml_url
      }
    end

    private

    def pdf_url_expires_at = model.file_url_expires_at

    def xml_url_expires_at = model.xml_url_expires_at
  end
end
