# frozen_string_literal: true

module LagoMcpClient
  # What a tool guard decides for one tool call: run it now, hold it until a person
  # confirms it, or refuse it with a message the model can relay.
  ToolDecision = Data.define(:action, :message) do
    def self.run = new(action: :run, message: nil)

    def self.confirm = new(action: :confirm, message: nil)

    def self.refuse(message) = new(action: :refuse, message:)

    def run? = action == :run

    def confirm? = action == :confirm

    def refuse? = action == :refuse
  end
end
