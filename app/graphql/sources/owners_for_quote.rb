# frozen_string_literal: true

# GraphQL DataLoader source for batch loading owners (users) for quotes.
#
# Prevents N+1 queries when fetching owners across multiple quotes
# in a single GraphQL query (e.g., `quotes { owners { ... } }`).
#
# Loads all QuoteOwner records for the given quote IDs (scoped to the current organization)
# in a single query, preloads associated users, and groups them by quote_id.
# Returns an array of users for each quote.
#
# Usage in GraphQL types:
#   dataloader.with(Sources::OwnersForQuote, current_organization).load(object.id)

module Sources
  class OwnersForQuote < GraphQL::Dataloader::Source
    def initialize(organization)
      @organization = organization
    end

    def fetch(quote_ids)
      quote_owners = QuoteOwner
        .where(quote_id: quote_ids, organization: @organization)
        .includes(:user)

      grouped = quote_owners.group_by(&:quote_id)

      quote_ids.map do |quote_id|
        (grouped[quote_id] || []).map(&:user)
      end
    end
  end
end
