import getStateNameFromAbbreviation from '../helpers/states.js';
import getCardDetailsByFriendlyName from '../helpers/credit-cards.js';

/*
 * fanatics.com checkout module — SCAFFOLD / WORK IN PROGRESS.
 *
 * This file mirrors the shape of the other modules in sites/ (see
 * demandware.js / footsites.js) so it can be dropped into the existing
 * sites[site_name] dispatch in helpers/cluster.js. It is NOT functional yet.
 *
 * Before this module can work you must:
 *   1. Replace every selector / endpoint marked `TODO` below with values
 *      captured from a real browser session against the live site
 *      (DevTools -> Elements for selectors, Network for cart/checkout XHRs).
 *      Use scripts/check-platform.ps1 against a HAR you export from your own
 *      browser to identify the underlying commerce platform first — if it is
 *      Shopify or Demandware you may be able to reuse those modules instead.
 *   2. Implement handling for fanatics.com's edge bot-mitigation. As of this
 *      writing the site is fronted by Akamai Bot Manager, which blocks
 *      automated requests before any HTML is served. The repo has no Akamai
 *      handling today (footsites.js only deals with DataDome). That piece is
 *      intentionally NOT implemented here and is left to the integrator.
 *
 * Until both are done, guestCheckout throws so it can never be mistaken for a
 * working integration.
 */

const IS_IMPLEMENTED = false;

// TODO: confirm against the live site whether sizes are radios/buttons, and
// whether a separate "style" dimension exists (footsites has one, demandware does not).
async function enterAddressDetails({ page, address, type }) {
  // TODO: replace all of these placeholder selectors with the real ones.
  const firstNameSelector = `input[name="${type}_firstName"]`;
  const lastNameSelector = `input[name="${type}_lastName"]`;
  const address1Selector = `input[name="${type}_address1"]`;
  const address2Selector = `input[name="${type}_address2"]`;
  const citySelector = `input[name="${type}_city"]`;
  const stateSelector = `select[name="${type}_state"]`;
  const postalCodeSelector = `input[name="${type}_zip"]`;
  const phoneNumberSelector = `input[name="${type}_phone"]`;

  await page.waitForSelector(firstNameSelector);
  await page.type(firstNameSelector, address.first_name, { delay: 10 });

  await page.waitForSelector(lastNameSelector);
  await page.type(lastNameSelector, address.last_name, { delay: 10 });

  await page.waitForSelector(address1Selector);
  await page.type(address1Selector, address.address_line_1, { delay: 10 });

  await page.waitForSelector(address2Selector);
  await page.type(address2Selector, address.address_line_2, { delay: 10 });

  await page.waitForSelector(citySelector);
  await page.type(citySelector, address.city, { delay: 10 });

  // TODO: confirm whether the state <select> uses the abbreviation (e.g. "NY")
  // or the full name. helpers/states.js converts abbreviation -> full name.
  try {
    await page.waitForSelector(stateSelector);
    await page.select(stateSelector, getStateNameFromAbbreviation(address.state));
  } catch (err) {
    // no-op if the state field is absent / pre-filled
  }

  await page.waitForSelector(postalCodeSelector);
  await page.type(postalCodeSelector, address.postal_code, { delay: 10 });

  await page.waitForSelector(phoneNumberSelector);
  await page.type(phoneNumberSelector, address.phone_number, { delay: 10 });
}

async function searchByProductCode({ taskLogger, page, productCode, domain }) {
  taskLogger.info('Searching for product by product code');
  // TODO: replace with the real search URL + result/product-page selectors.
  let searchResult;
  while (!searchResult) {
    await page.goto(`${domain}/search?query=${productCode}`, { waitUntil: 'domcontentloaded' });
    await Promise.all([
      (async () => {
        try {
          searchResult = await page.waitForSelector('TODO_SEARCH_RESULT_SELECTOR', { timeout: 5 * 1000 });
          await searchResult.click();
        } catch (err) {
          // no-op
        }
      })(),
      (async () => {
        try {
          searchResult = await page.waitForSelector('TODO_PRODUCT_DETAILS_SELECTOR', { timeout: 5 * 1000 });
          taskLogger.info('Navigated to product details page');
        } catch (err) {
          // no-op
        }
      })()
    ]);
  }
}

async function checkout({ taskLogger, page, domain, shippingAddress, shippingSpeedIndex, billingAddress, cardFriendlyName }) {
  let cardDetails = {
    cardNumber: process.env.CARD_NUMBER,
    nameOnCard: process.env.NAME_ON_CARD,
    expirationMonth: process.env.EXPIRATION_MONTH,
    expirationYear: process.env.EXPIRATION_YEAR,
    securityCode: process.env.SECURITY_CODE
  };
  if (cardFriendlyName) {
    cardDetails = getCardDetailsByFriendlyName(cardFriendlyName);
  }

  taskLogger.info('Navigating to checkout page');
  // TODO: confirm the real checkout URL/flow (single page vs. multi-step).
  await page.goto(`${domain}/checkout`, { waitUntil: 'domcontentloaded' });

  taskLogger.info('Entering shipping details');
  await enterAddressDetails({ page, address: shippingAddress, type: 'shipping' });

  // TODO: select shipping speed using shippingSpeedIndex against the real
  // shipping-options selector (see shopify.js / demandware.js for the pattern).
  taskLogger.info(`Selecting shipping speed index ${shippingSpeedIndex}`);

  taskLogger.info('Entering billing details');
  await enterAddressDetails({ page, address: billingAddress, type: 'billing' });

  // TODO: enter card details. Confirm whether the card inputs live inside
  // iframes (PCI) — if so use contentFrame() as in footsites.js / demandware.js.
  taskLogger.info(cardDetails.cardNumber ? 'Card details loaded' : 'Card details missing');

  // TODO: click the place-order button and return a real success signal.
  const checkoutComplete = false;
  return checkoutComplete;
}

const guestCheckout = async ({ taskLogger, page, url, productCode, size, shippingAddress, shippingSpeedIndex, billingAddress, cardFriendlyName }) => {
  if (!IS_IMPLEMENTED) {
    throw new Error(
      'sites/fanatics.js is a scaffold: replace the TODO selectors/endpoints with ' +
        'live values and implement Akamai Bot Manager handling before enabling. ' +
        'Set IS_IMPLEMENTED = true once done.'
    );
  }

  const domain = url.split('/').slice(0, 3).join('/');

  if (productCode) {
    await searchByProductCode({ taskLogger, page, productCode, domain });
  } else {
    taskLogger.info('No product code supplied, navigating to URL');
    await page.goto(url, { waitUntil: 'domcontentloaded' });
  }

  // TODO: select size and add to cart. Prefer the internal cart API if the
  // Network tab reveals one (see shopify.js / demandware.js); otherwise fall
  // back to clicking the size + add-to-cart selectors (see footsites.js).
  let isInCart = false;
  while (!isInCart) {
    taskLogger.info(`Attempting to add size ${size} to cart`);
    isInCart = false; // TODO: set true once ATC is confirmed
  }

  let checkoutComplete = false;
  if (isInCart) {
    checkoutComplete = await checkout({
      taskLogger,
      page,
      domain,
      shippingAddress,
      shippingSpeedIndex,
      billingAddress,
      cardFriendlyName
    });
  }

  return checkoutComplete;
};

export default guestCheckout;
