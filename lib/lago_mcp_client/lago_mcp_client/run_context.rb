# frozen_string_literal: true

module LagoMcpClient
  class ToolNotFoundError < StandardError
    attr_reader :tool_name

    def initialize(tool_name)
      @tool_name = tool_name
      super("Tool '#{tool_name}' not found")
    end
  end

  class RunContext
    # Results of the tool calls that ran or were refused, and the calls held for confirmation
    ToolCallsOutcome = Data.define(:results, :pending)

    attr_reader :client, :tool_guard

    # The tool guard, when given, answers `exposed?(name)` to filter the tools offered to the
    # model and `decide(name, arguments)` with a ToolDecision for every call the model makes.
    def initialize(client:, tool_guard: nil)
      @client = client
      @tool_guard = tool_guard
      @tools = []
      @tools_results = []
      @mutex = Mutex.new
    end

    def setup!
      @tools = client.list_tools
      @tools = @tools.select { |tool| tool_guard.exposed?(tool.name) } if tool_guard
      self
    end

    def to_model_tools
      @tools.map do |tool|
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: tool.input_schema
          }
        }
      end
    end

    def process_tool_calls(tool_calls)
      results = []
      pending = []

      tool_calls.each do |tool_call|
        function_name = tool_call.dig("function", "name")
        arguments = JSON.parse(tool_call.dig("function", "arguments").presence || "{}")
        decision = decide(function_name, arguments)

        if decision.confirm?
          pending << {tool_call_id: tool_call["id"], name: function_name, arguments:}
          next
        end

        result = decision.refuse? ? refusal(decision.message) : call_tool(function_name, arguments)
        results << tool_result(tool_call["id"], function_name, result)
      end

      ToolCallsOutcome.new(results:, pending:)
    end

    # Runs a call that a person confirmed. The guard is asked again, so a permission lost
    # since the confirmation was requested still refuses the call.
    def process_confirmed_tool_call(tool_call_id:, name:, arguments:)
      decision = decide(name, arguments)
      result = decision.refuse? ? refusal(decision.message) : call_tool(name, arguments)

      tool_result(tool_call_id, name, result)
    end

    private

    def decide(name, arguments)
      return ToolDecision.run unless tool_guard

      tool_guard.decide(name, arguments)
    end

    def tool_result(tool_call_id, name, result)
      {
        tool_call_id:,
        name:,
        role: "tool",
        content: JSON.generate(result)
      }
    end

    # Same shape as an MCP tool error, so the model reads it like any other tool output
    def refusal(message)
      {"content" => [{"type" => "text", "text" => message}], "isError" => true}
    end

    def get_tool(name)
      @tools.find { |tool| tool.name == name }
    end

    def call_tool(name, arguments = {})
      tool = get_tool(name)
      raise ToolNotFoundError.new(name) unless tool

      result = client.call_tool(name, arguments)
      @tools_results << {name => result}
      result
    end
  end
end
