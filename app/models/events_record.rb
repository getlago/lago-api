# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

class EventsRecord < ApplicationRecord
  self.abstract_class = true

  connects_to database: {writing: :events, reading: :events}
end
