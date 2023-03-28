#!/usr/bin/env ruby

# tools for analysis of solar production

require 'uri'
require 'net/http'
require 'json'
require 'date'

SITE1 = 'xxxxxxx'
SITE2 = 'yyyyyyy'
SITE1_TOKEN = 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'
SITE2_TOKEN = 'wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww'
 
class SolarProduction

  attr_accessor :total_prod, :max_prod, :avg_prod, :prod_by_date, :sunny_ratio, :avg_sunny_ratio, :name, :power_by_date
  
  def initialize()
    @total_prod = 0
    @max_prod = 0
    @avg_prod = 0
    @prod_by_date = {}
    @sunny_ratio = {}
    @avg_sunny_ratio = 0
    @name = ""
    @power_by_date = {}
  end

  def reset()
    @total_prod = 0
    @max_prod = 0
    @avg_prod = 0
    @prod_by_date = {}
    @sunny_ratio = {}
    @avg_sunny_ratio = 0
    @name = ""
    @power_by_date = {}
  end

  def read_csv(csv_file)
    puts "reading monthly production csv file #{csv_file}"
    @name = csv_file
    File.open(csv_file) do |fd|
      header = fd.gets
      fd.each_line do |line|
        fields = line.split(',')
        @prod_by_date[fields[0]] = fields[1][1..-2].to_f
      end
    end
  end

  # given a numeric year and month, return the start and end dates as strings
  def month_start_end(year, month)
    start = Date.new(year, month) # defaults to first day
    end_of_month = start.next_month.prev_day
    return start.to_s, end_of_month.to_s
  end

  # given a numeric year and month, return the start and end times as strings
  def month_start_end_time(year, month)
    start = Date.new(year, month) # defaults to first day
    end_of_month = start.next_month # midnight of this day
    midnight = '%2000:00:00'
    return start.to_s + midnight, end_of_month.to_s + midnight
  end

  # initialize energy, power and derived data via the api
  def init_api(year, month, token = SITE1_TOKEN, site = SITE1)
    reset()
    @name = "#{year}_#{month}"
    get_energy_api_month(year, month, token, site)
    get_power_api_month(year, month, token, site)
    analyze()
    report()
  end
  
  def get_energy_api_month(year, month, token = SITE1_TOKEN, site = SITE1)
    start_date, end_date = month_start_end(year, month)
    get_energy_api(start_date, end_date, token, site)
  end

  # use the energy API to get daily productio for a month, same as reading the csv
  def get_energy_api(start_date, end_date, token = SITE1_TOKEN, site = SITE1)
    uri = URI("https://monitoringapi.solaredge.com/site/#{site}/energy/?timeUnit=DAY&endDate=#{end_date}&startDate=#{start_date}&api_key=#{token}")
    res = Net::HTTP.get_response(uri)
    if res.is_a?(Net::HTTPSuccess)
      jstring = res.body
    else
      puts "http request failed"
      return 0
    end
    jo = JSON.parse jstring
    jo['energy']['values'].each do |date_value|
      date, time = date_value['date'].split(' ')
      energy = date_value['value']
      @prod_by_date[date] = energy.to_f
    end
  end

  def max_energy()
    max = 0
    max_date = ''
    @prod_by_date.each do |date, daily|
      if daily && daily > max
        max = daily
        max_date = date
      end
    end
    return max, max_date
  end
  
  def get_power_api_month(year, month, token = SITE1_TOKEN, site = SITE1)
    start_time, end_time = month_start_end_time(year, month)
    get_power_api(start_time, end_time, token, site)
  end

  # use the power api to get power at 15 minute intervals
  def get_power_api(start_time, end_time, token = SITE1_TOKEN, site = SITE1)
    uri = URI("https://monitoringapi.solaredge.com/site/#{site}/power?endTime=#{end_time}&startTime=#{start_time}&api_key=#{token}")
    res = Net::HTTP.get_response(uri)
    if res.is_a?(Net::HTTPSuccess)
      jstring = res.body
    else
      puts "http request failed"
      return 0
    end
    jo = JSON.parse jstring
    jo['power']['values'].each do |date_value|
      date, time = date_value['date'].split(' ')
      power = date_value['value']
      if @power_by_date.has_key?(date)
        @power_by_date[date][time] = power
      else
        @power_by_date[date] = {time => power}
      end
    end
  end

  def max_power()
    max = 0
    max_date = ''
    @power_by_date.each do |date, power_by_time|
      power_by_time.each_value do |power|
        if power && power > max
          max = power
          max_date = date
        end
      end
    end
    return max, max_date
  end

  def analyze()
    @total_prod = 0.0
    prod_by_date.each_value do |v|
      @total_prod += v
      @max_prod = v if v > @max_prod
    end
    @avg_prod = @total_prod / @prod_by_date.size
    sr_total = 0
    prod_by_date.each do |k, v|
      sr = v / @max_prod
      @sunny_ratio[k] = sr
      sr_total += sr
    end
    @avg_sunny_ratio = sr_total / @sunny_ratio.size
  end

  def report()
    puts "total production #{@total_prod}"
    maxe, maxe_date = max_energy()
    puts "max daily production #{maxe} on #{maxe_date}"
    maxp, maxp_date = max_power()
    puts "max power #{maxp} on #{maxp_date}"
    puts "average production #{@avg_prod.round(2)}"
    puts "average cloudiness #{(100 - (100 * @avg_sunny_ratio)).round(2)}%\n"
  end

  def compare(other)
    puts "comparing #{@name} with #{other.name}"
    tp_ratio = other.total_prod / @total_prod
    puts "total production for #{other.name} is #{(100 - (tp_ratio * 100)).round(2)}% lower"
    maxp, maxp_date = max_power()
    omaxp, omaxp_date = other.max_power()
    max_power_ratio = omaxp / maxp
    puts "max power for #{other.name} is #{(100 - (max_power_ratio * 100)).round(2)}% lower"
    maxe, maxe_date = max_power()
    omaxe, omaxe_date = other.max_power()
    max_daily_ratio = omaxe / maxe
    puts "max daily production for #{other.name} is #{(100 - (max_daily_ratio * 100)).round(2)}% lower\n"
  end

end

# sprod.rb <month> <year> <other-year[:<other-year>...]
if __FILE__ == $0

  unless ARGV.length == 3
    puts "usage: sprod.rb <month> <year> <other-year[:<other-year>...]"
    exit 1
  else
    target_month = ARGV[0].to_i
    target_year = ARGV[1].to_i
    other_years = ARGV[2].split(':').map{|yr| yr.to_i}
    puts "comparing #{target_month} #{target_year} with #{other_years}\n"
  end

  target = SolarProduction.new
  target.init_api(target_year, target_month)

  other_years.each do |year|
    puts ""
    other = SolarProduction.new
    other.init_api(year, target_month)
    other.compare(target)
  end
end


