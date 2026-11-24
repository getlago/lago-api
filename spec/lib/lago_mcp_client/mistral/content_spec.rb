# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoMcpClient::Mistral::Content do
  describe ".text" do
    it "returns a string as is" do
      expect(described_class.text("Hello")).to eq("Hello")
    end

    it "joins the text chunks and drops the thinking chunks" do
      content = [
        {"type" => "thinking", "thinking" => [{"type" => "text", "text" => "Let me check"}]},
        {"type" => "text", "text" => "Here are "},
        {"type" => "text", "text" => "the invoices"}
      ]

      expect(described_class.text(content)).to eq("Here are the invoices")
    end

    it "returns the text of a single chunk" do
      expect(described_class.text({"type" => "text", "text" => "Hi"})).to eq("Hi")
      expect(described_class.text({"type" => "thinking", "thinking" => []})).to eq("")
    end

    it "returns an empty string for anything else" do
      expect(described_class.text(nil)).to eq("")
      expect(described_class.text([{"type" => "tool_reference", "title" => "Doc"}])).to eq("")
    end
  end
end
