const puppeteer = require('puppeteer');
const fs = require('fs');

const LOGIN = 'specht';
const PASSWORD = '123456'; // not a leak, this only works in DEVELOPMENT ;-)

function delay(time) {
   return new Promise(function(resolve) {
       setTimeout(resolve, time)
   });
}

(async () => {
    console.log(`${new Date()} Launching script`);
    const browser = await puppeteer.launch({headless: true});
    const page = await browser.newPage();

    await page.setViewport({width: 900, height: 1200});
    await page.goto('http://localhost:8025');
    await page.waitForSelector('#email');
    await page.click('#email');
    await page.keyboard.type(LOGIN);
    await page.click('#submit');
    await page.waitForSelector('#code');
    await page.click('#code');
    await page.keyboard.type(PASSWORD);
    await page.click('#submit');
    await page.waitForNavigation({timeout: 0});

    let results = await page.evaluate(async () => {
        let res = await fetch('/api/get_all_user_ids');
        return await res.json();
    });

    for (let entry of results.users) {
        let email = entry[0];
        let id = entry[1];
        let path = entry[2];
        let display_name = entry[3];
        console.log(`${klasse} ${display_name}`);
        await page.goto(`http://localhost:8025/timetable/${id}`);
        await page.waitForSelector('.fc-view-harness', {timeout: 0});
        let dir = `./timetable_screenshots/${path}`;
        if (!fs.existsSync(dir))
            fs.mkdirSync(dir, { recursive: true });
        await page.screenshot({path: `${dir}/${display_name}.png`});
    }

    await browser.close();
})();
