pragma solidity ^0.8.0;

import {PythStructs} from "./PythStructs.sol";
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library PythPriceLib {
    int32 constant PD_EXPO = -9;
    uint64 constant PD_SCALE = 1_000_000_000;
    uint64 constant MAX_PD_V_U64 = (1 << 28) - 1;

    struct PriceStruct {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint publishTime;
    }

    function div(
        PriceStruct memory self,
        PriceStruct memory other
    ) public pure returns (PriceStruct memory) {
        require(other.price != 0, "Division by zero");

        uint64 base_price;
        int64 base_sign;
        uint64 other_price;
        int64 other_sign;
        (base_price, base_sign) = toUnsigned(self.price);
        (other_price, other_sign) = toUnsigned(other.price);

        uint64 midprice = (base_price * PD_SCALE) / other_price;
        int32 midprice_expo = self.expo - other.expo + PD_EXPO;

        uint64 other_confidence_pct = (other.conf * (PD_SCALE)) /
            uint64(other_price);

        uint128 conf = uint64(
            ((self.conf * PD_SCALE) / other_price) +
                ((other_confidence_pct) * midprice) /
                PD_SCALE
        );

        if (conf < MAX_PD_V_U64) {
            return
                PriceStruct(
                    int64(midprice) * base_sign * other_sign,
                    uint64(conf),
                    midprice_expo,
                    self.publishTime < other.publishTime
                        ? self.publishTime
                        : other.publishTime
                );
        } else {
            return PriceStruct(0, 0, 0, 0);
        }
    }

    function add(
        PriceStruct memory self,
        PriceStruct memory other
    ) public pure returns (PriceStruct memory) {
        require(self.expo == other.expo, "Exponents must match");

        int64 price = self.price + other.price;
        uint64 conf = self.conf + other.conf;

        return
            PriceStruct(
                price,
                conf,
                self.expo,
                self.publishTime < other.publishTime
                    ? self.publishTime
                    : other.publishTime
            );
    }

    function cmul(
        PriceStruct memory self,
        int64 c,
        int32 e
    ) public pure returns (PriceStruct memory) {
        return mul(self, PriceStruct(c, 0, e, self.publishTime));
    }

    function mul(
        PriceStruct memory self,
        PriceStruct memory other
    ) public pure returns (PriceStruct memory) {
        PriceStruct memory base = normalize(self);
        PriceStruct memory other_normalized = normalize(other);

        uint64 base_price;
        int64 base_sign;
        uint64 other_price;
        int64 other_sign;
        (base_price, base_sign) = toUnsigned(base.price);
        (other_price, other_sign) = toUnsigned(other_normalized.price);

        uint64 midprice = base_price * other_price;
        int32 midprice_expo = base.expo + other_normalized.expo;

        uint64 conf = uint64(
            base.conf * other_price + other_normalized.conf * base_price
        );

        return
            PriceStruct(
                int64(midprice) * base_sign * other_sign,
                conf,
                midprice_expo,
                self.publishTime < other.publishTime
                    ? self.publishTime
                    : other.publishTime
            );
    }

    function normalize(
        PriceStruct memory self
    ) public pure returns (PriceStruct memory) {
        uint64 p;
        int64 s;
        (p, s) = toUnsigned(self.price);
        uint64 c = self.conf;
        int32 e = self.expo;

        while (p > MAX_PD_V_U64 || c > MAX_PD_V_U64) {
            p /= 10;
            c /= 10;
            e += 1;
        }

        return PriceStruct(int64(p) * s, c, e, self.publishTime);
    }

    function toUnsigned(int64 x) private pure returns (uint64, int64) {
        if (x == type(int64).min) {
            return (type(uint64).max + 1, -1);
        } else if (x < 0) {
            return (uint64(-x), -1);
        } else {
            return (uint64(x), 1);
        }
    }
}
