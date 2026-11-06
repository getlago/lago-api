# frozen_string_literal: true

module AiConversations
  # Decides, for the member who owns the conversation, whether the AI agent may run a tool.
  # The agent never gets more than the member could do in the dashboard, and every write
  # waits for the member's confirmation.
  class ToolGuard
    def initialize(membership:)
      @membership = membership
    end

    def exposed?(tool_name)
      ToolPolicy.known?(tool_name)
    end

    def decide(tool_name, _arguments = {})
      unless ToolPolicy.known?(tool_name)
        return LagoMcpClient::ToolDecision.refuse(
          "The #{tool_name} tool is not available to the assistant. Tell the member this action cannot be done from the assistant."
        )
      end

      unless membership.active?
        return LagoMcpClient::ToolDecision.refuse(
          "The member no longer belongs to this organization. Do not perform any action."
        )
      end

      missing_permissions = ToolPolicy.missing_permissions(membership, tool_name)
      if missing_permissions.any?
        return LagoMcpClient::ToolDecision.refuse(
          "The member's role does not allow this action: the #{tool_name} tool needs the " \
          "#{missing_permissions.join(", ")} permission. Tell the member they cannot do this, " \
          "and that an admin of the organization can change their role. Do not try another way."
        )
      end

      ToolPolicy.rule(tool_name).write? ? LagoMcpClient::ToolDecision.confirm : LagoMcpClient::ToolDecision.run
    end

    private

    attr_reader :membership
  end
end
