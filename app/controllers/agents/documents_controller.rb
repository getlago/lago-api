# frozen_string_literal: true

module Agents
  class DocumentsController < BaseController
    def auth
      result = Agents::AuthDocumentService.call(storefront:)

      render(plain: result.document, content_type: "text/markdown")
    end

    def billing
      result = Agents::BillingDocumentService.call(storefront:)

      render(plain: result.document, content_type: "text/markdown")
    end
  end
end
