import { initUnits } from "./lib/format.js";
import { initMapLoader } from "./lib/map_loader.js";
import { initNearMe } from "./lib/near_me.js";
import { initRankedLists } from "./lib/ranked_list.js";
import { initSearch } from "./lib/search.js";
import { initSnowFilter } from "./lib/snow_filter.js";

// Bundled by esbuild into main.js (see the Rakefile assets task); each init is isolated so one failure can't take down the rest.
const safely = (init) => {
  try {
    return init();
  } catch (error) {
    console.error(error);
  }
};

const firstFormat = safely(initUnits);
safely(initSearch);

window.addEventListener("DOMContentLoaded", () => {
  safely(firstFormat);
  [initSnowFilter, initRankedLists, initMapLoader, initNearMe].forEach(safely);
});
