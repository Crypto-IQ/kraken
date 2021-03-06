module Main where

import Control.Concurrent
import Control.Monad
import Control.Monad.IO.Class
import qualified Data.ByteString.Char8 as BC (pack)
import Data.Default
import Data.Text
import System.Environment
import System.Exit

import Kraken.Rest
import Kraken.Types
import Kraken.Util

-----------------------------------------------------------------------------

main :: IO ()
main = getConfig >>= either (const exitFailure) run 
  
run :: Config -> IO ()
run cfg = void $ runKraken cfg $ do
  io =<< time
  io =<< assets         (AssetOptions Currency [XXBT,XETH])
  io =<< assetPairs     (AssetPairOptions AllInfo pairs)
  io =<< tickers        (TickerOptions pairs)
  io =<< ohlcs          (OHLCOptions xbtusd 60 Nothing)
  io =<< orderBook      (OrderBookOptions xbtusd (Just 5))
  io =<< trades         (TradesOptions xbtusd Nothing)
  io =<< spreads        (SpreadOptions xbtusd Nothing)
  io =<< accountBalance
  io =<< tradeBalance   (TradeBalanceOptions Nothing Nothing)
  io =<< openOrders     (OpenOrdersOptions True Nothing)
  io =<< closedOrders   def
  io =<< queryOrders    (QueryOrdersOptions False Nothing ["123"]) 
  io =<< tradesHistory  def
  io =<< queryTrades    (QueryTradesOptions ["123"] True)
  io =<< openPositions  (OpenPositionsOptions ["123"] False)
  io =<< ledgers        def
  io =<< queryLedgers   (QueryLedgersOptions ["123","321"])
  io =<< tradeVolume    (TradeVolumeOptions pairs)

 where

  io :: Show a => a -> KrakenT ()
  io t = liftIO $ print t >> putChar '\n' >> threadDelay 1000000
  
  xbtusd = AssetPair XXBT ZUSD
  xbteur = AssetPair XXBT ZEUR

  pairs  = [xbtusd,xbteur]

