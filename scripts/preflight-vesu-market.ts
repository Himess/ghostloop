import { preflightVesuMarket } from "../src/market/vesu-snapshot.js";

const result = await preflightVesuMarket();
console.log(JSON.stringify(result, null, 2));
if (!result.liveBorrowViable) process.exitCode = 1;
