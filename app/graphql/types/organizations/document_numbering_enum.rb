# frozen_string_literal: true

module Types
  module Organizations
    class DocumentNumberingEnum < Types::BaseEnum
      graphql_name 'DocumentNumberingEnum'

      Organization::DOCUMENT_NUMBERINGS.each do |type|
        value type
      end
    end
  end
end
