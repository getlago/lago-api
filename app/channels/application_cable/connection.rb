# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :connection_identifier

    def connect
      self.connection_identifier = SecureRandom.uuid
    end
  end
end
