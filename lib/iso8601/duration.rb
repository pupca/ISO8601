# encoding: utf-8

module ISO8601
  ##
  # A duration representation. When no base is provided, all atoms use an
  # average factor which affects the result of any computation like `#to_seconds`.
  #
  # @example
  #     d = ISO8601::Duration.new('P2Y1MT2H')
  #     d.years  # => #<ISO8601::Years:0x000000051adee8 @atom=2.0, @base=nil>
  #     d.months # => #<ISO8601::Months:0x00000004f230b0 @atom=1.0, @base=nil>
  #     d.days   # => #<ISO8601::Days:0x00000005205468 @atom=0, @base=nil>
  #     d.hours  # => #<ISO8601::Hours:0x000000051e02a8 @atom=2.0, @base=nil>
  #     d.to_seconds # => 65707200.0
  #
  # @example Explicit base date time
  #     d = ISO8601::Duration.new('P2Y1MT2H', ISO8601::DateTime.new('2014-08017'))
  #     d.years  # => #<ISO8601::Years:0x000000051adee8 @atom=2.0, @base=#<ISO8601::DateTime...>>
  #     d.months # => #<ISO8601::Months:0x00000004f230b0 @atom=1.0, @base=#<ISO8601::DateTime...>>
  #     d.days   # => #<ISO8601::Days:0x00000005205468 @atom=0, @base=#<ISO8601::DateTime...>>
  #     d.hours  # => #<ISO8601::Hours:0x000000051e02a8 @atom=2.0, @base=#<ISO8601::DateTime...>>
  #     d.to_seconds # => 65757600.0
  #
  # @example Number of seconds versus patterns
  #     di = ISO8601::Duration.new(65707200)
  #     dp = ISO8601::Duration.new('P2Y1MT2H')
  #     ds = ISO8601::Duration.new('P65707200S')
  #     di == dp # => true
  #     di == ds # => true
  #
  class Duration
    ##
    # @param [String, Numeric] input The duration pattern
    # @param [ISO8601::DateTime, nil] base (nil) The base datetime to
    #   calculate the duration against an specific point in time.
    def initialize(input, base = nil)
      @original = input
      @pattern = to_pattern
      @atoms = atomize(@pattern)
      @base = base
      valid_base?
    end
    ##
    # Raw atoms result of parsing the given pattern.
    #
    # @return [Hash<Float>]
    attr_reader :atoms
    ##
    # Datetime base.
    #
    # @return [ISO8601::DateTime, nil]
    attr_reader :base
    ##
    # Assigns a new base datetime
    #
    # @return [ISO8601::DateTime, nil]
    def base=(value)
      @base = value
      valid_base?
      @base
    end
    ##
    # @return [String] The string representation of the duration
    attr_reader :pattern
    alias_method :to_s, :pattern
    ##
    # @return [ISO8601::Years] The years of the duration
    def years
      ISO8601::Years.new(atoms[:years], base)
    end
    ##
    # @return [ISO8601::Months] The months of the duration
    def months
      # Changes the base to compute the months for the right base year
      month_base = base.nil? ? nil : base + years.to_seconds
      ISO8601::Months.new(atoms[:months], month_base)
    end
    ##
    # @return [ISO8601::Weeks] The weeks of the duration
    def weeks
      ISO8601::Weeks.new(atoms[:weeks], base)
    end
    ##
    # @return [ISO8601::Days] The days of the duration
    def days
      ISO8601::Days.new(atoms[:days], base)
    end
    ##
    # @return [ISO8601::Hours] The hours of the duration
    def hours
      ISO8601::Hours.new(atoms[:hours], base)
    end
    ##
    # @return [ISO8601::Minutes] The minutes of the duration
    def minutes
      ISO8601::Minutes.new(atoms[:minutes], base)
    end
    ##
    # @return [ISO8601::Seconds] The seconds of the duration
    def seconds
      ISO8601::Seconds.new(atoms[:seconds], base)
    end
    ##
    # The Integer representation of the duration sign.
    #
    # @return [Integer]
    attr_reader :sign
    ##
    # @return [ISO8601::Duration] The absolute representation of the duration
    def abs
      self.class.new(pattern.sub(/^[-+]/, ''), base)
    end
    ##
    # Addition
    #
    # @param [ISO8601::Duration] duration The duration to add
    #
    # @raise [ISO8601::Errors::DurationBaseError] If bases doesn't match
    # @return [ISO8601::Duration]
    def +(duration)
      compare_bases(duration)

      d1 = to_seconds
      d2 = duration.to_seconds

      seconds_to_iso(d1 + d2)
    end
    ##
    # Substraction
    #
    # @param [ISO8601::Duration] duration The duration to substract
    #
    # @raise [ISO8601::Errors::DurationBaseError] If bases doesn't match
    # @return [ISO8601::Duration]
    def -(duration)
      compare_bases(duration)

      d1 = to_seconds
      d2 = duration.to_seconds
      result = d1 - d2

      return self.class.new('PT0S') if result == 0

      seconds_to_iso(result)
    end
    ##
    # @param [ISO8601::Duration] duration The duration to compare
    #
    # @raise [ISO8601::Errors::DurationBaseError] If bases doesn't match
    # @return [Boolean]
    def ==(duration)
      compare_bases(duration)

      (to_seconds == duration.to_seconds)
    end
    ##
    # @param [ISO8601::Duration] duration The duration to compare
    #
    # @return [Boolean]
    def eql?(duration)
      (hash == duration.hash)
    end
    ##
    # @return [Fixnum]
    def hash
      [atoms.values, self.class].hash
    end
    ##
    # Converts original input into  a valid ISO 8601 duration pattern.
    #
    # @return [String]
    def to_pattern
      (@original.kind_of? Numeric) ? "PT#{@original}S" : @original
    end
    ##
    # @return [Numeric] The duration in seconds
    def to_seconds
      [years, months, weeks, days, hours, minutes, seconds].map(&:to_seconds).reduce(&:+)
    end


    private
    ##
    # Splits a duration pattern into valid atoms.
    #
    # Acceptable patterns:
    #
    # * PnYnMnD
    # * PTnHnMnS
    # * PnYnMnDTnHnMnS
    # * PnW
    #
    # Where `n` is any number. If it contains a decimal fraction, a dot (`.`) or
    # comma (`,`) can be used.
    #
    # @param [String] input
    #
    # @return [Hash<Float>]
    def atomize(input)
      duration = input.match(/^
        (?<sign>\+|-)?
        P(?:
          (?:
            (?:(?<years>\d+(?:[,.]\d+)?)Y)?
            (?:(?<months>\d+(?:[.,]\d+)?)M)?
            (?:(?<days>\d+(?:[.,]\d+)?)D)?
            (?<time>T
              (?:(?<hours>\d+(?:[.,]\d+)?)H)?
              (?:(?<minutes>\d+(?:[.,]\d+)?)M)?
              (?:(?<seconds>\d+(?:[.,]\d+)?)S)?
            )?
          ) |
          (?<weeks>\d+(?:[.,]\d+)?W)
        ) # Duration
      $/x) or raise ISO8601::Errors::UnknownPattern.new(input)

      valid_pattern?(duration)

      @sign = (duration[:sign].nil? || duration[:sign] == '+') ? 1 : -1

      keys = duration.names.map(&:to_sym)
      values = duration.captures.map { |v| v.to_f * sign }
      components = Hash[keys.zip(values)]
      components.delete(:time) # clean time capture

      valid_fractions?(components.values)

      components
    end
    ##
    # @param [Numeric] duration The seconds to promote
    #
    # @return [ISO8601::Duration]
    def seconds_to_iso(duration)
      sign = '-' if (duration < 0)
      duration = duration.abs
      years, y_mod = (duration / self.years.factor).to_i, (duration % self.years.factor)
      months, m_mod = (y_mod / self.months.factor).to_i, (y_mod % self.months.factor)
      days, d_mod = (m_mod / self.days.factor).to_i, (m_mod % self.days.factor)
      hours, h_mod = (d_mod / self.hours.factor).to_i, (d_mod % self.hours.factor)
      minutes, mi_mod = (h_mod / self.minutes.factor).to_i, (h_mod % self.minutes.factor)
      seconds = mi_mod.div(1) == mi_mod ? mi_mod.to_i : mi_mod.to_f # Coerce to Integer when needed (`PT1S` instead of `PT1.0S`)

      seconds = (seconds != 0 or (years == 0 and months == 0 and days == 0 and hours == 0 and minutes == 0)) ? "#{seconds}S" : ""
      minutes = (minutes != 0) ? "#{minutes}M" : ""
      hours = (hours != 0) ? "#{hours}H" : ""
      days = (days != 0) ? "#{days}D" : ""
      months = (months != 0) ? "#{months}M" : ""
      years = (years != 0) ? "#{years}Y" : ""

      date = %[#{sign}P#{years}#{months}#{days}]
      time = (hours != "" or minutes != "" or seconds != "") ? %[T#{hours}#{minutes}#{seconds}] : ""
      date_time = date + time
      return ISO8601::Duration.new(date_time)
    end

    def valid_base?
      if !(base.nil? or base.kind_of? ISO8601::DateTime)
        raise TypeError
      end
    end
    def valid_pattern?(components)
      date = [components[:years], components[:months], components[:days]].compact
      time = [components[:hours], components[:minutes], components[:seconds]].compact
      weeks = components[:weeks]
      all = [date, time, weeks].flatten.compact

      if all.empty? || (!components[:time].nil? && time.empty? && weeks.nil?)
        raise ISO8601::Errors::UnknownPattern.new(@pattern)
      end
    end

    def valid_fractions?(values)
      values = values.reject(&:zero?)
      fractions = values.select { |a| (a % 1) != 0 }
      if fractions.size > 1 || (fractions.size == 1 && fractions.last != values.last)
        raise ISO8601::Errors::InvalidFractions.new(@pattern)
      end
    end

    def compare_bases(duration)
      raise ISO8601::Errors::DurationBaseError.new(duration) if base.to_s != duration.base.to_s
    end
  end
end
