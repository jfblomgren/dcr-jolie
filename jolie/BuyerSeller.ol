from services.Buyer import BuyerInterface
from services.Seller import SellerInterface

service BuyerSeller {
    outputPort Buyer {
        location: "socket://localhost:8000"
        protocol: sodep
        interfaces: BuyerInterface
    }

    outputPort Seller {
        location: "socket://localhost:8001"
        protocol: sodep
        interfaces: SellerInterface
    }

    main {
        Item@Buyer("Pen")()
        Budget@Buyer(1000)()
        Request@Buyer()()
        Quote@Seller()()
        Order@Buyer()()
        Ship@Seller()()
    }
}