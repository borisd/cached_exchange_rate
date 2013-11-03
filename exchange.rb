require 'open_exchange_rates'

OPEN_EXCHANGE_KEY = GLOBAL['open_exchange_key']

module Cache
  def self.add(value, key, period)
    $redis.set(key, value)
    $redis.expire(key, period)
    value || 0
  end
  def self.clear(keys)
    $redis.del(keys) unless keys.blank?
  end
end

module Prices
  CURRENCY_UPDATE_PERIOD = 1.hour

  def self.clear_cache
    Rails.logger.info "cleared redis cache: #{self.all_keys}"
    Cache.clear(self.all_keys)
  end

  module Currency

    def self.respond_to?(method_sym, include_private = false)
      method_sym.to_s =~ /[a-z]+_to_[a-z]+/ ? true : super
    end

    def self.method_missing(method_sym, *arguments, &block)
      if method_sym.to_s =~ /([a-z]+)_to_([a-z]+)/
        conversion($1.upcase, $2.upcase, arguments[0] || 1)
      else
        super
      end
    end

    def self.to_parts(price)
      [price.round, price.modulo(1)]
    end

    private

    def self.conversion(from, to, amount = 1)
      ($redis.get(self.key(from, to)) || update_currency(from, to)).to_f * amount
    end

    def self.update_currency(from = 'USD', to = 'ILS')
      begin
      @oe ||= OpenExchangeRates::Rates.new(:app_id => OPEN_EXCHANGE_KEY)
      rescue Exception => e
        Rails.logger.error("Can't get info from open exchange: #{e.message}")
        @oe = 0
      end
      Cache.add(@oe.exchange_rate(:from => from, :to => to), self.key(from, to), CURRENCY_UPDATE_PERIOD)
    end

    def self.key(from, to)
      "prices:rate:#{from}:#{to}"
    end
  end

  private

    def self.all_keys
      $redis.keys('prices:*')
    end
end
