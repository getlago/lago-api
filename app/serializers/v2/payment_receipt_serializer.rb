# frozen_string_literal: true

module V2
  class PaymentReceiptSerializer < ModelSerializer
    PRELOADS = [:organization, {file_attachment: :blob}, {xml_file_attachment: :blob}].freeze

    timestamps :pdf_url_expires_at, :xml_url_expires_at, :created_at, :updated_at
    expandable :payment, serializer: ::V2::PaymentSerializer

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
