# frozen_string_literal: true

module PaperTrailTraceable
  extend ActiveSupport::Concern

  included do
    has_paper_trail(
      meta: {
        whodunnit: proc { |_| CurrentContext.membership }
      }
    )
  end
end
