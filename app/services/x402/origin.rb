# frozen_string_literal: true

module X402
  module Origin
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1]].freeze

    def self.normalize(value)
      uri = parse(value)

      if bare?(uri) && (uri.scheme.downcase == "https" || LOOPBACK_HOSTS.include?(uri.host.downcase))
        format(uri)
      end
    end

    def self.of(url)
      uri = parse(url)

      if uri && uri.userinfo.nil?
        format(uri)
      end
    end

    def self.host(origin)
      origin.to_s.split("://", 2).last
    end

    def self.parse(value)
      return unless value.is_a?(String)

      uri = URI.parse(value)
      uri if uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      nil
    end
    private_class_method :parse

    def self.bare?(uri)
      !uri.nil? && uri.path.in?(["", "/"]) && uri.query.nil? && uri.fragment.nil? && uri.userinfo.nil?
    end
    private_class_method :bare?

    def self.format(uri)
      port = (uri.port == uri.default_port) ? "" : ":#{uri.port}"

      "#{uri.scheme.downcase}://#{uri.host.downcase}#{port}"
    end
    private_class_method :format
  end
end
