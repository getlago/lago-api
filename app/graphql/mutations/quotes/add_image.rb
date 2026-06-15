# frozen_string_literal: true

module Mutations
  module Quotes
    class AddImage < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "quotes:update"

      graphql_name "AddQuoteImage"
      description "Upload an image for a quote and return its URL"

      argument :id, ID, required: true
      argument :image, String, required: true

      field :url, String, null: false

      def resolve(id:, image:)
        quote = current_organization.quotes.find_by(id:)
        result = ::Quotes::AddImageService.call(quote:, image:)

        result.success? ? {url: result.image_url} : result_error(result)
      end
    end
  end
end
