require 'v8/to'

module Kernel
  def display_exception(exception)
    puts "#{exception.class}: #{exception.message}"
    exception.backtrace.each { |line| puts ' ' * 4 + line }
  end
end

class Object
  def ==(other)
    if @native && @native.respond_to?(:Equals) && other_native = other.instance_variable_get(:@native)
      @native.Equals(other_native)
    else
      super
    end
  end
end

module V8
  def self.js_property?(obj, name)
    obj.respond_to?(:js_property?) && obj.js_property?(name)
  end

  module To
    # got to use ruby_class, not class, therefor overwrite the whole thing
    def self.v8(value)
      case value
      when V8::Object
        value.instance_eval {@native}
      when String
        C::String::New(value.to_s)
      when Symbol
        C::String::NewSymbol(value.to_s)
      when Proc,Method
        template = C::FunctionTemplate::New() do |arguments|
          rbargs = []
          for i in 0..arguments.Length() - 1
            rbargs << To.rb(arguments[i])
          end
          V8::Function.rubycall(value, *rbargs)
        end
        return template.GetFunction()
      when ::Array
        C::Array::New(value.length).tap do |a|
          value.each_with_index do |item, i|
            a.Set(i, To.v8(item))
          end
        end
      when ::Hash
        C::Object::New().tap do |o|
          value.each do |key, value|
            o.Set(To.v8(key), To.v8(value))
          end
        end
      when ::Time
        C::Date::New(value)
      when ::Class
        Constructors[value].GetFunction().tap do |f|
          f.SetHiddenValue(C::String::NewSymbol("TheRubyRacer::RubyObject"), C::External::New(value))
        end
      when nil, Numeric, TrueClass, FalseClass, C::Value
        value
      else
        args = C::Array::New(1)
        args.Set(0, C::External::New(value))
        Access[value.ruby_class].GetFunction().NewInstance(args)
      end
    rescue Exception => exception
      display_exception(exception)
      C::Empty
    end
  end

  class NamedPropertyGetter
    def self.call(property, info)
      obj  = To.rb(info.This())
      name = To.rb(property)

      if V8.js_property?(obj, name)
        Function.rubycall(obj.method(name))
      elsif obj.respond_to?(name)
        To.v8(obj.method(name))
      elsif obj.respond_to?(:[])
        # rescue: workaround for "TypeError: can't convert String into Integer"
        # on Nokogiri::XML::Nodeset being called with, e.g., obj['nodeType']
        To.v8(obj[name]) rescue nil
      else
        C::Empty
      end
    rescue Exception => exception
      display_exception(exception)
      C::Empty
    end
  end

  class NamedPropertySetter
    def self.call(property, value, info)
      obj     = To.rb(info.This())
      name    = To.rb(property)
      rbvalue = To.rb(value)

      if obj.respond_to?("#{name}=")
        obj.send("#{name}=", rbvalue)
      elsif obj.respond_to?(:[]=)
        obj.send(:[]=, rbvalue)
      else
        define_property(obj, name)
        obj.send("#{name}=", rbvalue)
      end

      To.v8(value)
    rescue Exception => exception
      display_exception(exception)
      C::Empty
    end

    def self.define_property(obj, name)
      (class << obj; self; end).property(name)
    end
  end
end