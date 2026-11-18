# frozen_string_literal: true

module LagoMcpClient
  module Mistral
    # Mistral returns message content either as a string or, for reasoning models, as a list of
    # chunks such as `{"type" => "thinking", ...}` and `{"type" => "text", "text" => "..."}`.
    # Only the text chunks are meant for the member: the thinking chunks are the model's reasoning.
    module Content
      def self.text(content)
        case content
        when String then content
        when Array then content.map { |chunk| text(chunk) }.join
        when Hash then (content["type"] == "text") ? content["text"].to_s : ""
        else ""
        end
      end
    end
  end
end
