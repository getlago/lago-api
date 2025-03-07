# frozen_string_literal: true

module Mutations
  module PaymentReceipts
    class Download < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "payment_receipts:view"

      graphql_name "DownloadPaymentReceipt"
      description "Download an PaymentReceipt PDF"

      argument :id, ID, required: true

      type Types::PaymentReceipts::Object

      def resolve(id:)
        payment_receipt = PaymentReceipt.find_by(id:, organization_id: current_organization.id)
        result = ::PaymentReceipts::GeneratePdfService.call(payment_receipt:)
        result.success? ? result.payment_receipt : result_error(result)
      end
    end
  end
end
