class WidgetSanityChecker
  attr_accessor :pattern
  def parse(args)
    @pattern = args[0]
    self
  end

  def widget_and_report_names
    # export file?
    if File.exist?(@pattern)
      filename = @pattern
      yaml = YAML.load(IO.read(filename))
      if yaml.kind_of?(Array)
        # export file
        yaml.map do |widget|
          widget = widget["MiqWidget"] if widget["MiqWidget"]
          if widget["resource_type"] != "MiqReport"
            puts "skipping #{filename}:: #{widget["resource_type"]}"
            nil
          else
            resource_name = widget["resource_name"]
            rpt = if(rpt_yaml = widget["MiqReportContent"])
                    MiqReport.new(rpt_yaml.first["MiqReport"])
                  end
            [widget["title"], widget, resource_name || rpt.name, rpt]
          end
        end.compact
      else
        # single report file
        [[filename, yaml, yaml["resource_name"], yaml["MiqReportContent"]]]
      end
    else
      Dir.glob("product/dashboard/widgets/*").map do |filename|
        yaml = YAML.load(IO.read(filename))
        if yaml["resource_type"] != "MiqReport"
          puts "skipping #{filename}:: #{yaml["resource_type"]}"
          nil
        else
          [filename, yaml, yaml["resource_name"], yaml["MiqReportContent"]]
        end
      end.compact
    end
  end

  def run
    checker = ReportSanityChecker.new
    widget_and_report_names.each do |widget, widget_yaml, rpt_name, rpt|
      # could have loaded the yaml file with the report name, but this is easier
      rpt ||= MiqReport.find_by(name: rpt_name)
      puts "", "# WIDGET: #{widget}"
# skipping timezone saves a lot of performance time
# options:
#   :timezone_matters: false
      puts "# TIMEZONE MATTERS: #{widget_yaml["options"][:timezone_matters]}" if widget_yaml["options"].try(:key?, :timezone_matters)
      puts "# REPORT: #{rpt_name}", ""
      if rpt
        checker.check_report(rpt)
      else
        puts "ERROR: Couldn't find #{rpt_name}"
      end
    end.size
  end

  def self.run(argv = ARGV)
    checker = new.parse(argv).run
  end
end
