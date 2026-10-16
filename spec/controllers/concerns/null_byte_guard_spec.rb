# frozen_string_literal: true

require "rails_helper"

RSpec.describe NullByteGuard do
  def build_request(path: "/api/v1/customers", body: nil, content_type: "application/json")
    env = Rack::MockRequest.env_for(path, :method => body ? "POST" : "GET", :input => body, "CONTENT_TYPE" => content_type)
    ActionDispatch::Request.new(env)
  end

  describe ".contains_null_byte?" do
    it "detects a percent-encoded null byte in the URL" do
      expect(described_class.contains_null_byte?(build_request(path: "/api/v1/customers?search_term=a%00b"))).to be(true)
    end

    it "detects an escaped null byte in a JSON body" do
      expect(described_class.contains_null_byte?(build_request(body: '{"name":"a\\u0000b"}'))).to be(true)
    end

    it "detects a percent-encoded null byte in a form body" do
      request = build_request(body: "name=a%00b", content_type: "application/x-www-form-urlencoded")

      expect(described_class.contains_null_byte?(request)).to be(true)
    end

    it "returns false for a regular request" do
      expect(described_class.contains_null_byte?(build_request(path: "/api/v1/customers?search_term=foo"))).to be(false)
      expect(described_class.contains_null_byte?(build_request(body: '{"name":"foo"}'))).to be(false)
    end
  end

  describe ".strip_needed?" do
    it "is true when the request contains a null byte" do
      expect(described_class.strip_needed?(build_request(body: '{"name":"a\\u0000b"}'))).to be(true)
    end

    it "is always true for multipart requests, whose binary body is not scanned" do
      request = build_request(body: "--x--", content_type: "multipart/form-data; boundary=x")

      expect(described_class.strip_needed?(request)).to be(true)
    end

    it "is false for a regular request" do
      expect(described_class.strip_needed?(build_request(body: '{"name":"foo"}'))).to be(false)
    end
  end

  describe ".sanitize_params!" do
    it "strips the parameters when needed" do
      params = ActionController::Parameters.new(name: "a\u0000b")

      described_class.sanitize_params!(build_request(path: "/api/v1/customers?name=a%00b"), params)

      expect(params[:name]).to eq("ab")
    end

    it "leaves the parameters untouched otherwise" do
      params = ActionController::Parameters.new(name: "foo")
      allow(described_class).to receive(:strip_params!)

      described_class.sanitize_params!(build_request(path: "/api/v1/customers?name=foo"), params)

      expect(described_class).not_to have_received(:strip_params!)
    end

    it "cleans multipart text fields and leaves uploaded files untouched" do
      file = Rack::Test::UploadedFile.new(StringIO.new("binary\u0000content"), "application/octet-stream", original_filename: "data.bin")
      params = ActionController::Parameters.new(name: "a\u0000b", file:)
      request = build_request(body: "--x--", content_type: "multipart/form-data; boundary=x")

      described_class.sanitize_params!(request, params)

      expect(params[:name]).to eq("ab")
      expect(params[:file]).to be(file)
    end
  end

  describe ".sanitize" do
    it "strips the value when needed and returns it as is otherwise" do
      value = {"name" => "a\u0000b"}

      expect(described_class.sanitize(build_request(body: '{"name":"a\\u0000b"}'), value)).to eq({"name" => "ab"})
      expect(described_class.sanitize(build_request(body: '{"name":"foo"}'), value)).to be(value)
    end
  end

  describe ".strip" do
    it "removes null bytes from nested strings and keys" do
      value = {"na\u0000me" => "a\u0000b", "list" => ["c\u0000", 1, nil], "nested" => {"x" => "\u0000"}}

      expect(described_class.strip(value)).to eq({"name" => "ab", "list" => ["c", 1, nil], "nested" => {"x" => ""}})
    end
  end

  describe ".strip_params!" do
    it "removes null bytes from parameter values" do
      params = ActionController::Parameters.new(
        search_term: "a\u0000b",
        filters: {codes: ["c\u0000d"]},
        events: [{code: "e\u0000f", properties: {value: 1}}]
      )

      described_class.strip_params!(params)

      expect(params[:search_term]).to eq("ab")
      expect(params[:filters][:codes]).to eq(["cd"])
      expect(params[:events].first[:code]).to eq("ef")
      expect(params[:events].first[:properties][:value]).to eq(1)
    end

    it "removes null bytes from parameter keys" do
      params = ActionController::Parameters.new(properties: {"bad\u0000key" => "x", "ok" => "y"})

      described_class.strip_params!(params)

      expect(params[:properties].to_unsafe_h).to eq({"badkey" => "x", "ok" => "y"})
    end
  end
end
