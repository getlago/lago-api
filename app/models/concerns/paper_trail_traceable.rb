# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module PaperTrailTraceable
  extend ActiveSupport::Concern

  included do
    has_paper_trail(
      meta: {
        whodunnit: proc { |_| CurrentContext.membership },
        lago_version: LAGO_VERSION.number
      }
    )
  end
end
