# frozen_string_literal: true

require "rails_helper"

describe X402::Origin do
  describe ".normalize" do
    {
      "https://api.example.com" => "https://api.example.com",
      "https://api.example.com/" => "https://api.example.com",
      "HTTPS://API.Example.COM" => "https://api.example.com",
      "https://api.example.com:443" => "https://api.example.com",
      "https://api.example.com:8443" => "https://api.example.com:8443",
      "http://localhost:3000" => "http://localhost:3000",
      "http://localhost:80" => "http://localhost",
      "http://127.0.0.1:3000" => "http://127.0.0.1:3000",
      "http://[::1]:3000" => "http://[::1]:3000",
      "https://api.example.com:65535" => "https://api.example.com:65535",
      "https://pay-1.xn--bcher-kva.example" => "https://pay-1.xn--bcher-kva.example",
      "https://api.example.com:65536" => nil,
      "https://api.example.com:0" => nil,
      "https://*.example.com" => nil,
      "https://api_v1.example.com" => nil,
      "https://api..example.com" => nil,
      "http://api.example.com" => nil,
      "https://api.example.com/v1" => nil,
      "https://api.example.com?x=1" => nil,
      "https://api.example.com/#top" => nil,
      "https://user:pass@api.example.com" => nil,
      "ftp://api.example.com" => nil,
      "api.example.com" => nil,
      " https://api.example.com" => nil,
      "https://" => nil,
      42 => nil,
      nil => nil
    }.each do |input, expected|
      it("normalizes #{input.inspect} to #{expected.inspect}") { expect(described_class.normalize(input)).to eq(expected) }
    end
  end

  describe ".of" do
    {
      "https://api.example.com/v1/generate?x=1#y" => "https://api.example.com",
      "https://API.example.com:443/v1" => "https://api.example.com",
      "http://localhost:3000/v1" => "http://localhost:3000",
      "https://user@api.example.com/v1" => nil,
      "ftp://api.example.com/v1" => nil,
      "urn:example:1" => nil,
      "not a url" => nil
    }.each do |input, expected|
      it("reads #{expected.inspect} from #{input.inspect}") { expect(described_class.of(input)).to eq(expected) }
    end
  end

  describe ".host" do
    {
      "https://api.example.com" => "api.example.com",
      "http://localhost:3000" => "localhost:3000",
      "http://[::1]:3000" => "[::1]:3000"
    }.each do |origin, expected|
      it("reads #{expected} from #{origin}") { expect(described_class.host(origin)).to eq(expected) }
    end
  end
end
