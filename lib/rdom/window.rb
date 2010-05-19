require 'open-uri'
require 'johnson/tracemonkey'
require 'johnson/js_land_proxy_patch'

module RDom
  class Window
    autoload :Console,   'rdom/window/console.rb'
    autoload :Frame,     'rdom/window/frame.rb'
    autoload :History,   'rdom/window/history.rb'
    autoload :Navigator, 'rdom/window/navigator.rb'
    autoload :Screen,    'rdom/window/screen.rb'
    autoload :Timers,    'rdom/window/timers.rb'

    include Decoration, Event::Target, Window::Timers

    properties :location, :navigator, :url, :console, :parent, :name, :document,
               :defaultStatus, :history, :opener, :frames, :innerHeight, :innerWidth,
               :outerHeight, :outerWidth, :pageXOffset, :pageYOffset, :screenX,
               :screenY, :screenLeft, :screenTop

    attr_accessor *PROPERTIES

    def initialize(*args)
      options  = args.last.is_a?(Hash) ? args.pop : {}
      html     = args.pop

      @name    = options[:name]
      @parent  = options[:parent] || self
      @opener  = options[:opener]
      @frames  = []
      @screen  = Screen.new(self)
      @history = History.new

      load(html, options) if html
    end

    def runtime
      @runtime ||= Johnson::Runtime.new.tap do |runtime|
        runtime['window']    = self
        runtime['document']  = document
        runtime['location']  = location
        runtime['navigator'] = navigator
        runtime['console']   = console
      end
    end

    def load(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      url     = uri?(args.first) || file?(args.first) ? args.shift.gsub(%r(^file://), '') : options[:url]
      html    = args.shift || (url ? open(url).read : raise("can't load without either html or url"))

      location.send(:set, url) if url
      load_document(html, url, options)
      load_scripts
      load_frames
      trigger_load_event
      Window::Timers::Task.run_all
    end

    def evaluate(script, file = nil, line = nil)
      runtime.evaluate(script, file, line, self, self)
    end

    def normalize_uri(uri)
      location.uri.normalize.merge(uri)
    end

    def close
    end

    def location
      @location ||= Location.new(self)
    end

    def url
      location.href
    end

    def location=(uri)
      if location.href == uri
        location.reload
      elsif location.href == 'about:blank'
        location.assign(uri)
      else
        location.replace(uri)
      end
    end

    def navigator
      @navigator ||= Navigator.new
    end

    def getComputedStyle
      raise(NotImplementedError.new("not implemented: #{self.class.name}#getComputedStyle"))
    end

    def console
      @console ||= Console.new
    end

    def log(line)
      console.log(line)
    end

    def print(output)
      p output
    end

    protected

      def load_document(html, url, options = {})
        flags = 1 << 1 | 1 << 2 | 1 << 3 | 1 << 4 | 1 << 5 | 1 << 6
        @document = Document.new(self, html, options.merge(:url => url))
      end

      def load_scripts
        document.getElementsByTagName('script').each do |script|
          process_script(script)
        end
      end

      def load_script(uri)
        script = open(normalize_uri(uri))
        script = script.string if script.respond_to?(:string)
        script = script.read   if script.respond_to?(:read)
        evaluate(script, uri)
      end

      def load_frames
        document.getElementsByTagName('iframe').each { |frame| load_frame(frame) }
      end

      def load_frame(node)
        frame = Frame.new(:parent => self, :name => node.getAttribute('name'))
        frame.location.href = normalize_uri(node.getAttribute('src')) if node.getAttribute('src')
        frames << frame
      end

      def trigger_load_event
        event = document.createEvent('Events')
        event.initEvent('load')
        dispatchEvent(event)
      end
      
      def process_script(script)
        src = script.getAttribute('src')
        src && !src.empty? ? load_script(src) : evaluate(script.textContent)
      end

      def uri?(arg)
        uri = URI.parse(arg)
        %w(file http https).include?(uri.scheme)
      rescue
        false
      end

      def file?(arg)
        arg.to_s[0, 1] == '/'
      end
  end
end