{-# LANGUAGE KindSignatures #-}

module Kraken.Rest where

import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Trans.Either
import           Control.Monad.Trans.Reader
import           Crypto.Hash
import           Data.Aeson.Types
import           Data.Byteable
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import           Data.Monoid
import           Data.Proxy
import           Data.Text (Text)
import           Data.Text.Encoding (decodeUtf8)
import           Data.Time
import           Data.Time.Clock.POSIX
import           GHC.TypeLits
import           Servant.API
import           Servant.Client

import           Kraken.Types

-----------------------------------------------------------------------------

restHost :: Host
restHost = "api.kraken.com"

restPort :: Port
restPort = 443

-----------------------------------------------------------------------------

type ServantT = EitherT ServantError IO
type KrakenT  = ReaderT Config ServantT

runKraken :: Config -> KrakenT a -> IO (Either ServantError a)
runKraken cfg = runEitherT . flip runReaderT cfg

-----------------------------------------------------------------------------

type KrakenAPI             = TimeService
                        :<|> AssetService
                        :<|> AssetPairService
                        :<|> TickerService
                        :<|> OHLCService
                        :<|> OrderBookService
                        :<|> TradesService
                        :<|> SpreadService
                        :<|> AccountBalanceService
                        :<|> TradeBalanceService
                        :<|> OpenOrdersService
                        :<|> ClosedOrdersService
                        :<|> QueryOrdersService
                        :<|> TradesHistoryService
                        :<|> QueryTradesService
                        :<|> OpenPositionsService
                        :<|> LedgersService
                        :<|> QueryLedgersService
                        :<|> TradeVolumeService

type TimeService           = PublicService  "Time"          ()                   Time
type AssetService          = PublicService  "Assets"        AssetOptions         Assets
type AssetPairService      = PublicService  "AssetPairs"    AssetPairOptions     AssetPairs
type TickerService         = PublicService  "Ticker"        TickerOptions        Tickers
type OHLCService           = PublicService  "OHLC"          OHLCOptions          OHLCs
type OrderBookService      = PublicService  "Depth"         OrderBookOptions     OrderBook
type TradesService         = PublicService  "Trades"        TradesOptions        Trades
type SpreadService         = PublicService  "Spread"        SpreadOptions        Spreads
type AccountBalanceService = PrivateService "Balance"       ()                   Value
type TradeBalanceService   = PrivateService "TradeBalance"  TradeBalanceOptions  Value
type OpenOrdersService     = PrivateService "OpenOrders"    OpenOrdersOptions    Value
type ClosedOrdersService   = PrivateService "ClosedOrders"  ClosedOrdersOptions  Value
type QueryOrdersService    = PrivateService "QueryOrders"   QueryOrdersOptions   Value
type TradesHistoryService  = PrivateService "TradeHistory"  TradesHistoryOptions Value
type QueryTradesService    = PrivateService "QueryTrades"   QueryTradesOptions   Value
type OpenPositionsService  = PrivateService "OpenPositions" OpenPositionsOptions Value
type LedgersService        = PrivateService "Ledgers"       LedgersOptions       Value
type QueryLedgersService   = PrivateService "QueryLedgers"  QueryLedgersOptions  Value
type TradeVolumeService    = PrivateService "TradeVolume"   TradeVolumeOptions   Value

-----------------------------------------------------------------------------

type APIVersion            = "0"
type Public                = "public"
type Private               = "private"

-----------------------------------------------------------------------------

type PublicService 
     (a :: Symbol) b c     = APIVersion
                             :> Public
                             :> a
                             :> ReqBody '[FormUrlEncoded] b
                             :> Post '[JSON] c
type PrivateService
     (a :: Symbol) b c     = APIVersion
                             :> Private
                             :> a
                             :> Header "API-Key" Text
                             :> Header "API-Sign" Text
                             :> ReqBody '[FormUrlEncoded] (PrivateRequest b)
                             :> Post '[JSON] c

-----------------------------------------------------------------------------

api :: Proxy KrakenAPI
api = Proxy

-----------------------------------------------------------------------------

time_           :: () -> ServantT Time
assets_         :: AssetOptions -> ServantT Assets
assetPairs_     :: AssetPairOptions -> ServantT AssetPairs
tickers_        :: TickerOptions -> ServantT Tickers
ohlcs_          :: OHLCOptions -> ServantT OHLCs
orderBook_      :: OrderBookOptions -> ServantT OrderBook
trades_         :: TradesOptions -> ServantT Trades
spreads_        :: SpreadOptions -> ServantT Spreads
accountBalance_ :: Maybe Text -> Maybe Text -> PrivateRequest () -> ServantT Value
tradeBalance_   :: Maybe Text -> Maybe Text -> PrivateRequest TradeBalanceOptions -> ServantT Value
openOrders_     :: Maybe Text -> Maybe Text -> PrivateRequest OpenOrdersOptions -> ServantT Value
closedOrders_   :: Maybe Text -> Maybe Text -> PrivateRequest ClosedOrdersOptions -> ServantT Value
queryOrders_    :: Maybe Text -> Maybe Text -> PrivateRequest QueryOrdersOptions -> ServantT Value
tradesHistory_  :: Maybe Text -> Maybe Text -> PrivateRequest TradesHistoryOptions -> ServantT Value
queryTrades_    :: Maybe Text -> Maybe Text -> PrivateRequest QueryTradesOptions -> ServantT Value
openPositions_  :: Maybe Text -> Maybe Text -> PrivateRequest OpenPositionsOptions -> ServantT Value
ledgers_        :: Maybe Text -> Maybe Text -> PrivateRequest LedgersOptions -> ServantT Value
queryLedgers_   :: Maybe Text -> Maybe Text -> PrivateRequest QueryLedgersOptions -> ServantT Value
tradeVolume_    :: Maybe Text -> Maybe Text -> PrivateRequest TradeVolumeOptions -> ServantT Value

time_
  :<|> assets_
  :<|> assetPairs_
  :<|> tickers_
  :<|> ohlcs_
  :<|> orderBook_
  :<|> trades_
  :<|> spreads_
  :<|> accountBalance_ 
  :<|> tradeBalance_
  :<|> openOrders_
  :<|> closedOrders_
  :<|> queryOrders_
  :<|> tradesHistory_
  :<|> queryTrades_
  :<|> openPositions_
  :<|> ledgers_
  :<|> queryLedgers_
  :<|> tradeVolume_  = client api (BaseUrl Https restHost restPort)

-----------------------------------------------------------------------------

privateRequest :: ToFormUrlEncoded a =>
                  String ->
                  a ->
                  (Maybe Text -> Maybe Text -> PrivateRequest a -> ServantT b) ->
                  KrakenT b
privateRequest url d f = do
  Config{..}       <- ask
  utcTime          <- liftIO getCurrentTime
  let apiKey       =  decodeUtf8 configAPIKey
      uri          =  BC.pack $ "/" <> url
      nonce        =  fromEnum . utcTimeToPOSIXSeconds $ utcTime
      privReq      =  PrivateRequest nonce configPassword d
      postData     =  BL.toStrict $ mimeRender (Proxy :: Proxy FormUrlEncoded) privReq
      nonceBytes   =  BC.pack . show $ nonce
      hashPostData =  toBytes (hash (nonceBytes <> postData) :: Digest SHA256)
      msg          =  uri <> hashPostData
      hmacMsg      =  hmac configPrivateKey msg :: HMAC SHA512
      apiSign      =  decodeUtf8 . B64.encode . toBytes $ hmacMsg
  lift $ f (Just apiKey) (Just apiSign) privReq

-----------------------------------------------------------------------------

time :: KrakenT Time
time = lift $ time_ ()

assets :: AssetOptions -> KrakenT Assets
assets = lift . assets_

assetPairs :: AssetPairOptions -> KrakenT AssetPairs
assetPairs = lift . assetPairs_

tickers :: TickerOptions -> KrakenT Tickers
tickers = lift . tickers_

ohlcs :: OHLCOptions -> KrakenT OHLCs
ohlcs = lift . ohlcs_

orderBook :: OrderBookOptions -> KrakenT OrderBook
orderBook = lift . orderBook_

trades :: TradesOptions -> KrakenT Trades
trades = lift . trades_

spreads :: SpreadOptions -> KrakenT Spreads
spreads = lift . spreads_

accountBalance :: KrakenT Value
accountBalance = privateRequest 
  (show . safeLink api $ (Proxy :: Proxy AccountBalanceService))
  ()
  accountBalance_

tradeBalance :: TradeBalanceOptions -> KrakenT Value
tradeBalance opts = privateRequest
  (show . safeLink api $ (Proxy :: Proxy TradeBalanceService))
  opts
  tradeBalance_

openOrders :: OpenOrdersOptions -> KrakenT Value
openOrders opts = privateRequest
  (show . safeLink api $ (Proxy :: Proxy OpenOrdersService))
  opts
  openOrders_

closedOrders :: ClosedOrdersOptions -> KrakenT Value
closedOrders opts = privateRequest
  (show . safeLink api $ (Proxy :: Proxy ClosedOrdersService))
  opts
  closedOrders_

queryOrders :: QueryOrdersOptions -> KrakenT Value
queryOrders opts = privateRequest
  (show . safeLink api $ (Proxy :: Proxy QueryOrdersService))
  opts
  queryOrders_

tradesHistory :: TradesHistoryOptions -> KrakenT Value
tradesHistory opts = privateRequest
  (show . safeLink api $ (Proxy :: Proxy TradesHistoryService))
  opts
  tradesHistory_

queryTrades :: QueryTradesOptions -> KrakenT Value
queryTrades opts = privateRequest
  (show . safeLink api $ (Proxy :: Proxy QueryTradesService))
  opts
  queryTrades_

openPositions :: OpenPositionsOptions -> KrakenT Value
openPositions opts = privateRequest
  (show . safeLink api $ (Proxy :: Proxy OpenPositionsService))
  opts
  openPositions_

ledgers :: LedgersOptions -> KrakenT Value
ledgers opts = privateRequest
  (show . safeLink api $ (Proxy :: Proxy LedgersService))
  opts
  ledgers_

queryLedgers :: QueryLedgersOptions -> KrakenT Value
queryLedgers opts = privateRequest
  (show . safeLink api $ (Proxy :: Proxy QueryLedgersService))
  opts
  queryLedgers_

tradeVolume :: TradeVolumeOptions -> KrakenT Value
tradeVolume opts = privateRequest
  (show . safeLink api $ (Proxy :: Proxy TradeVolumeService))
  opts
  tradeVolume_


