
# class to help print a table
# used in a few places, but this is for report sanity checker
# formatting turned out to be a bad idea - would be nice to remove

# planning on swapping this out for https://github.com/tj/terminal-table
# getting it to work first, then that is the next task (famous last words "NEXT")

class ReportSanityChecker
  class Table
    attr_accessor :headings

    def initialize
      # current max width for the column
      @sizes = []

      @headings = []
      @data = []
    end

    # configure padding for a column
    def pad(col, values)
      @sizes[col] =
        if values.kind_of?(Numeric)
          [@sizes[col] || 0, values].max
        else
          (values.map { |v| v.try(&:size) || 0 } << (@sizes[col] || 0)).max
        end
    end

    def print_hdr(*values)
      print "| "
      values.each_with_index do |value, col|
        print fmt(col, value), " | "
      end
      print "\n"
    end

    # TODO: add ":" to l/r pad
    def print_dash
      print "|"
      print *@sizes.each_with_index.map { |_, i| ":" + "-" * (sizes(i) || 3) + "-" + "|" }
      print "\n"
    end

    def print_col(*values)
      print "| "
      values.each_with_index do |value, col|
        print fmt(col, value), " | "
      end
      print "\n"
    end

    def <<(row)
      row.each_with_index { |d, i| pad(i, [d]) }
      @data << row
    end

    def print_all
      @headings.each_with_index { |h, i| pad(i, [h]) }

      print_hdr(*@headings)
      print_dash
      @data.each do |row|
        print_col(*row)
      end
    end

    private
    # formatter for a string
    NUTTIN = -> (value, size) { value }
    RPAD = -> (value, size) { "%*s" % [size, value] }
    LPAD = -> (value, size) { "%-*s" % [size, value] }
    FORMATTING = { :right => RPAD, :left => LPAD }.freeze

    private

    def sizes(col) ; @sizes[col] ; end
    def fmt(col, val)
      LPAD.call(val, sizes(col))
    end
    def align(col) ; :left ; end

    def f_to_s(f, tgt = 1)
      if f.kind_of?(Numeric)
        parts = f.round(tgt).to_s.split('.')
        parts[0].gsub!(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
        parts.join('.')
      else
        (f || "")
      end
    end

    def z_to_s(f, tgt = 1)
      f.kind_of?(Numeric) && f.round(tgt) == 0.0 ? nil : f_to_s(f, tgt)
    end
  end
end
