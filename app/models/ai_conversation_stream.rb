class AiConversationStream
  attr_reader :chunk, :done

  def initialize(chunk:, done:)
    @chunk = chunk
    @done = done
  end
end
