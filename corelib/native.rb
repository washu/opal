module Kernel
  def native?(value)
    `value == null || !value._klass`
  end

  def Native(obj)
    if native?(obj)
      Native.new(obj)
    else
      obj
    end
  end
end

class Native
  module Base
    module Helpers
      def alias_native(new, old)
        define_method new do |*args|
          Native.call(@native, old, *args)
        end
      end
    end

    def self.included?(klass)
      klass.instance_eval {
        extend Helpers
      }
    end

    def initialize(native)
      unless native?(native)
        raise ArgumentError, "the passed value isn't native"
      end

      @native = native
    end

    def to_n
      @native
    end
  end

  def self.try_convert(value)
    %x{
      if (#{native?(value)}) {
        return #{value}.valueOf();
      }
      else if (#{value.respond_to? :to_n}) {
        return #{value.to_n};
      }
      else {
        return nil;
      }
    }
  end

  def self.convert(value)
    native = try_convert(value)

    if `#{native} === nil`
      raise ArgumentError, "the passed value isn't a native"
    end

    native
  end

  def self.call(obj, key, *args, &block)
    args << block if block

    %x{
      var prop = #{obj}[#{key}];

      if (prop == null) {
        return nil;
      }
      else if (prop instanceof Function) {
        var result = prop.apply(#{obj}, #{args});

        return result == null ? nil : result;
      }
      else if (#{native?(`prop`)}) {
        return #{Native(`prop`)};
      }
      else {
        return prop;
      }
    }
  end

  include Base

  def nil?
    `#@native == null`
  end

  def each
    return Enumerator.new(self, :each) unless block_given?

    %x{
      for (var key in #@native) {
        #{yield `key`, `#@native[key]`}
      }
    }

    self
  end

  def [](key)
    raise 'cannot get value from nil native' if nil?

    %x{
      var prop = #@native[key];

      if (prop instanceof Function) {
        return prop;
      }
      else {
        return #{::Native.call(@native, key)}
      }
    }
  end

  def []=(key, value)
    raise 'cannot set value on nil native' if nil?

    native = Native.try_convert(value)

    if `#{native} === nil`
      `#@native[key] = #{value}`
    else
      `#@native[key] = #{native}`
    end
  end

  def method_missing(mid, *args, &block)
    raise 'cannot call method from nil native' if nil?

    %x{
      if (mid.charAt(mid.length - 1) === '=') {
        return #{self[mid.slice(0, mid.length - 1)] = args[0]};
      }
      else {
        return #{::Native.call(@native, mid, *args, &block)};
      }
    }
  end
end
