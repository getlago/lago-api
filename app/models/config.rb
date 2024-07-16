# frozen_string_literal: true

class Config
  def self.load(value)
    new(value || {})
  end

  def self.dump(value)
    DottedHash.new(value.to_h).to_h
  end

  def initialize(hash)
    @hash = DottedHash.new(default).merge(DottedHash.new(hash)).to_h
  end

  def [](key)
    @hash[key]
  end

  def to_h
    @hash.dup
  end

  def inspect
    "(#{self.class.name}) \n\t #{to_h.inspect}\n"
  end

  def default
    {}
  end

  def reset
    @hash = DottedHash.new(default).to_h
  end
end
