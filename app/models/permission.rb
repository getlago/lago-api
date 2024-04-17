# frozen_string_literal: true

class Hash
  def to_dotted_hash(recursive_key: '', separator: '.')
    each_with_object({}) do |(k, v), ret|
      key = recursive_key + k.to_s
      if v.is_a? Hash
        ret.merge!(v.to_dotted_hash(recursive_key: key + separator, separator:))
      else
        ret[key] = v
      end
    end
  end
end

class Permission < ApplicationRecord
  belongs_to :membership

  def self.all_permissions
    DEFAULT_PERMISSIONS_HASH.merge(YAML.parse_file(Rails.root.join('app/config/permissions/template-analyst.yml'))
      .to_ruby
      .to_dotted_hash(separator: ':')
      .keys.each_with_object({}) do |v, memo|
        memo[v] = true
        memo
      end)
  end

  # rubocop:disable Layout/ClassStructure
  ADMIN_PERMISSIONS_HASH = all_permissions.each_with_object({}) do |v, memo|
    memo[v] = true
    memo
  end.freeze

  DEFAULT_PERMISSIONS_HASH = all_permissions.each_with_object({}) do |v, memo|
    memo[v] = false
    memo
  end.freeze
  # rubocop:enable Layout/ClassStructure
end
