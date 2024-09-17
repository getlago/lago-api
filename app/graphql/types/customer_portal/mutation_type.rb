# frozen_string_literal: true

module Types
  module CustomerPortal
    class MutationType < Types::BaseObject
      field :download_customer_portal_invoice, mutation: Mutations::CustomerPortal::DownloadInvoice
    end
  end
end
