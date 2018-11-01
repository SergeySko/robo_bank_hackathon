pragma solidity >=0.4.24 <0.6.0;
 
import "github.com/Arachnid/solidity-stringutils/strings.sol";
 
contract RoboBank7 {
    using strings for *;
    
    struct DayEntry {
        mapping(uint8 => HourEntry) childs;
        uint sum;
        uint percent;
    }
    
    struct HourEntry {
        DayEntry parent;
        mapping(uint8 => MinuteEntry) childs;
        uint sum;
    }
    
    struct MinuteEntry {
        HourEntry parent;
        mapping(uint => Operation) operations;
        uint count;
        uint sum;
    }
    
    struct Operation {
        uint startTime;
        uint endTime;
        uint sum;
        uint percent;
        address clientAddress;
    }
    
    struct WhiteClient {
        address clientAddress;
        uint rating; // рейтинг
        uint usedRating; // выбранный рейтинг
    }
    
    struct BlackClient {
        address clientAddress;
        Operation[] credits;
    }
    
    address private owner;  // владелец 
    
    mapping(address => WhiteClient) private whiteList;
    mapping(address => BlackClient) private blackList;
    address[] whiteListKeys;
    address[] blackListKeys;
    
    uint8 _percentDeposit;
    uint8 _percentCredit;
    uint8 _creditLossPercent;
    uint8 _depCredIndexInPercent;
    uint _capital;
    uint _minutePriceForDeposit;
    uint _minutePriceForCredit;
    uint8 _k_riska;
    uint _creditAmount;    
    uint _creditPercents;

    
    DayEntry private deposits;
    
    constructor () public payable {
    	owner = msg.sender;
    	deposits = DayEntry(0, 0);
    
    	_percentDeposit = 5;
    	_percentCredit = 10;
    	_k_riska = 7;
    	_capital = msg.value; 
    	uint16 year = DateTime.getYear(now);
    	bool isLeapYear = DateTime.isLeapYear(year);
    	uint minuteInYear;
    	if (isLeapYear) {
    		minuteInYear = 366*24*60;
        
    	} else {
    		minuteInYear = 365*24*60;
    	}
    	_minutePriceForDeposit = _percentDeposit * 1e16 / minuteInYear;
    	_minutePriceForCredit = _percentCredit * 1e16 / minuteInYear;
    	
    	WhiteClient memory whiteClient1 = WhiteClient(0xCA35b7d915458EF540aDe6068dFe2F44E8fa733c, 30, 30);
    	WhiteClient memory whiteClient2 = WhiteClient(0x4b0897b0513fdc7c541b6d9d7e929c4e5364d2db, 30, 30);
    	whiteList[0xCA35b7d915458EF540aDe6068dFe2F44E8fa733c] = whiteClient1;
    	whiteListKeys.push(0xCA35b7d915458EF540aDe6068dFe2F44E8fa733c);
    	whiteList[0x4b0897b0513fdc7c541b6d9d7e929c4e5364d2db] = whiteClient1;
    	whiteListKeys.push(0x4b0897b0513fdc7c541b6d9d7e929c4e5364d2db);
    }
    
    // TODO - убрать возвращение строки
    // Дима
    function putDeposit(uint8 period) public payable returns (string) {
        bytes memory result;
        uint startTime = now;
        
        Operation memory operation = Operation(startTime, 
                                        startTime + (period * 60), 
                                        msg.value, 
                                        calculatePercent(1, period, msg.value),
                                        msg.sender);
        
        require(canGetDeposit(operation), 
            "Депозит не может быть принят, пора снижать ставку!"
        );
        
        // увеличим сумму дня
        deposits.sum = deposits.sum + operation.sum;
        deposits.percent = deposits.percent + operation.percent;
        
        uint8 hour = DateTime.getHour(operation.endTime);
        
        if (deposits.childs[hour].sum == 0) {
            deposits.childs[hour] = HourEntry(deposits, operation.sum);
            result = "create hour";
        } else {
            result = "exists hour";
        }
        
        HourEntry storage hourEntry = deposits.childs[hour]; 
        // увеличим сумму часа
        hourEntry.sum = hourEntry.sum + operation.sum;
            
        uint8 minute = DateTime.getMinute(operation.endTime);
        
        if (hourEntry.childs[minute].sum == 0) {
            hourEntry.childs[minute] = MinuteEntry(hourEntry, 0, operation.sum);
            result = ConcatHelper.concat(result, ", create minute");
        } else {
            result = ConcatHelper.concat(result, ", exists minute");
        }
        
        MinuteEntry storage minuteEntry = hourEntry.childs[minute]; 
        // увеличим сумму минуты
        minuteEntry.sum = minuteEntry.sum + operation.sum;
        minuteEntry.operations[minuteEntry.count] = operation;
        minuteEntry.count = minuteEntry.count + 1;
        
        owner.transfer(msg.value);
        
        sendEvent(2, operation.endTime);
        
        return string(result);
    }
    
    function canBeDepositPut(uint depositSum) internal returns (bool) {
        uint creditLoss = _creditAmount*_creditLossPercent/100;
        uint totalLoss = deposits.percent + creditLoss;
        uint totalEarnPlusCapital = _creditPercents + _capital;
        return totalLoss < totalEarnPlusCapital * _depCredIndexInPercent / 100;
        
    }
    
    // TODO перенести код в returnDeposits
    // TODO имплементировать удаление часа
    // Дима
    function returnDepositTest(uint8 day, uint8 hour, uint8 minute) public payable returns (string) {
        bytes memory result;
        
        if (deposits.childs[hour].sum != 0) {
            HourEntry hourEntry = deposits.childs[hour];
            result = "hour found";
         
            if (hourEntry.childs[minute].sum == 0) {
                MinuteEntry minuteEntry = hourEntry.childs[minute];
                result = ConcatHelper.concat(result, ", minute found");
                
                for (uint i=0; i<minuteEntry.count; i++) {
                    minuteEntry.operations[i].clientAddress.transfer(minuteEntry.operations[i].sum + minuteEntry.operations[i].percent);     
                    _capital = _capital - minuteEntry.operations[i].percent;
                }
                
                delete hourEntry.childs[minute];
                
                result = ConcatHelper.concat(result, ", deposits returned");
            } else {
                result = ConcatHelper.concat(result, ", minute not found");
            }
        } else {
            result = "hour not found";
        }
        
        return string(result);
    }
    
    // рассылка депозитов и проверка дефолтов по кредитам    
    // typeEvent = 0 - кредит и депозит, 1 - кредит, 2 - депозит
    function watchDog(uint8 typeEvent, uint8 day, uint8 hour, uint8 minute) public payable {
        require(msg.sender == owner);
        
        if (typeEvent == 1 || typeEvent == 0) {
            checkCredits(day, hour, minute);
        }
        
        if (typeEvent == 2 || typeEvent == 0) {
            returnDeposits(day, hour, minute);
        }
    }
    
    // установка значений процентов
    function setSetings(uint8 percentDeposit, uint8 percentCredit) public payable {
        require(msg.sender == owner);
        require(percentDeposit < percentCredit, "Процент по депозиту должен быть меньше процента по кредиту");
        
        _percentDeposit = percentCredit;
        _percentCredit = percentCredit;
    }
    
    
    // отсылка белого листа
    // Сергей
    function getWhiteList() public view returns (string) {
        string memory result = "[";
        require(msg.sender == owner);
        for (uint i = 0; i < whiteListKeys.length; i++) {
            if (i != 0) {
                result =conc(result, ",");
            }
            address currentAddress = whiteListKeys[i];
            WhiteClient currentWhiteClient = whiteList[currentAddress];
            result = conc(result, conc(conc(conc("{address:",address2str(currentAddress)),getWhiteClient(currentWhiteClient)),"}"));
        }
        result = conc(result, "]");
        return result;
    }
    
    function getWhiteClient(WhiteClient whiteClient) internal returns (string) {
        string memory result;
        return conc(conc(",rating:", uint2str(whiteClient.rating)), conc(",usedRating:", uint2str(whiteClient.usedRating)));
    }
    
    // отсылка белого листа
    // Сергей
    function getMinuteCost() public view returns (uint) {
        require(msg.sender == owner);
        return _minutePriceForCredit;
    }
    
    
    // отсылка черного листа
    // Сергей
    function getBlackList() public view returns (string) {
        require(msg.sender == owner);
        // TODO нужно имплементировать
    }
    
    function kill() public {
        require(msg.sender == owner);
        selfdestruct(msg.sender);
    }
    
    // проверяем, хватит ли капитала чтобы отдать
    // сумма процентов депозитов должна быть меньше (капитал + сумма процентов по кредиту - (сумма потерь процентов по дефолту)) 
    // Дима
    function canGetDeposit(Operation operation) internal returns (bool) {
        // TODO - нужно имплементировать
        return true;
    }
    
    // возвращаем депозиты на дату
    // Дима
    function returnDeposits(uint8 day, uint8 hour, uint8 minute) internal {
        // TODO - после отладки перенести код сюда из returnDepositTest
    }
    
    // проверяем кредиты на дату, если есть, то переносим их в черный список 
    // Андрей
    function checkCredits(uint8 day, uint8 hour, uint8 minute) internal {
        // TODO - нужно имплементировать
    }
    
    // распределение кредита по депозитам
    // true - если удалось
    // false - если нет
    // Дима
    function allocationCreditSum(Operation creditOperation) internal returns (bool) {
        // TODO  - нужно имплементировать
        return true;
    }
    
    // уведомление о операции, 
    // typeEvent = 1 - кредит, typeEvent = 2 - депозит
    // Миша
    function sendEvent(uint8 typeEvent, uint timeCallWatchDog) internal {
        // TODO - нужно имплементировать 
    }
    
    // если адрес есть в черном листе верни -1, 
    // иначе если есть в белом списке верни рейтинг
    // если не нашел то верни 1
    // Андрей
    function getAccessibleRating(address clientAddress) internal returns (uint) {
        WhiteClient whiteClient = whiteList[clientAddress];
        return whiteClient.rating - whiteClient.usedRating;
    } 
    
    // увеличь выбранный рейтинг
    // Сергей
    function updateUsedRating(address clientAddress, uint usedRating) internal {
        WhiteClient whiteClient = whiteList[clientAddress];
        whiteClient.usedRating -= usedRating;
    }
    
    // увеличь рейтинг и уменьши выбранный рейтинг 
    // Сергей
    function updateRatings(address clientAddress, uint usedRating, uint creditNumber) internal {
        WhiteClient whiteClient = whiteList[clientAddress];
        whiteClient.usedRating += usedRating;
        uint currentRating = whiteClient.rating;
        whiteClient.rating *= usedRating/currentRating * _k_riska * (1 + 1 / creditNumber) / 10;
    }
    
    // расчет процентов в год, typeEvent = 1 - кредит, typeEvent = 2 - депозит
    // Сергей
    function calculatePercent(uint8 typeEvent, uint period, uint sum) public view returns (uint) {
        //  TODO - нужно имплементировать
        if (typeEvent == 1) {
	        return sum * 1e18 * period * _minutePriceForDeposit;
        } else if (typeEvent == 2) {
	        return sum * 1e18 * period * _minutePriceForCredit;
        }
        return 0;
    }
    
     function conc(string s1, string s2) internal returns(string) {
        return s1.toSlice().concat(s2.toSlice());
    }
    
    function uint2str(uint i) internal pure returns (string) {
        if (i == 0) return "0";
        uint j = i;
        uint length;
        while (j != 0){
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint k = length - 1;
        while (i != 0){
            bstr[k--] = byte(48 + i % 10);
            i /= 10;
        }
        return string(bstr);
    }
    
    function address2str(address x) returns (string) {
        bytes memory b = new bytes(20);
        for (uint i = 0; i < 20; i++)
            b[i] = byte(uint8(uint(x) / (2**(8*(19 - i)))));
        return string(b);
    }
}

library ConcatHelper {
    function concat(bytes memory a, bytes memory b) internal pure returns (bytes memory) {
        return abi.encodePacked(a, b);
    }
}

library DateTime {
        /*
         *  Date and Time utilities for ethereum contracts
         *
         */
        struct _DateTime {
                uint16 year;
                uint8 month;
                uint8 day;
                uint8 hour;
                uint8 minute;
                uint8 second;
                uint8 weekday;
        }

        uint constant DAY_IN_SECONDS = 86400;
        uint constant public YEAR_IN_SECONDS = 31536000;
        uint constant public LEAP_YEAR_IN_SECONDS = 31622400;

        uint constant HOUR_IN_SECONDS = 3600;
        uint constant MINUTE_IN_SECONDS = 60;

        uint16 constant ORIGIN_YEAR = 1970;

        function isLeapYear(uint16 year) public pure returns (bool) {
                if (year % 4 != 0) {
                        return false;
                }
                if (year % 100 != 0) {
                        return true;
                }
                if (year % 400 != 0) {
                        return false;
                }
                return true;
        }

        function leapYearsBefore(uint year) public pure returns (uint) {
                year -= 1;
                return year / 4 - year / 100 + year / 400;
        }

        function getDaysInMonth(uint8 month, uint16 year) public pure returns (uint8) {
                if (month == 1 || month == 3 || month == 5 || month == 7 || month == 8 || month == 10 || month == 12) {
                        return 31;
                }
                else if (month == 4 || month == 6 || month == 9 || month == 11) {
                        return 30;
                }
                else if (isLeapYear(year)) {
                        return 29;
                }
                else {
                        return 28;
                }
        }

        function parseTimestamp(uint timestamp) internal pure returns (_DateTime dt) {
                uint secondsAccountedFor = 0;
                uint buf;
                uint8 i;

                // Year
                dt.year = getYear(timestamp);
                buf = leapYearsBefore(dt.year) - leapYearsBefore(ORIGIN_YEAR);

                secondsAccountedFor += LEAP_YEAR_IN_SECONDS * buf;
                secondsAccountedFor += YEAR_IN_SECONDS * (dt.year - ORIGIN_YEAR - buf);

                // Month
                uint secondsInMonth;
                for (i = 1; i <= 12; i++) {
                        secondsInMonth = DAY_IN_SECONDS * getDaysInMonth(i, dt.year);
                        if (secondsInMonth + secondsAccountedFor > timestamp) {
                                dt.month = i;
                                break;
                        }
                        secondsAccountedFor += secondsInMonth;
                }

                // Day
                for (i = 1; i <= getDaysInMonth(dt.month, dt.year); i++) {
                        if (DAY_IN_SECONDS + secondsAccountedFor > timestamp) {
                                dt.day = i;
                                break;
                        }
                        secondsAccountedFor += DAY_IN_SECONDS;
                }

                // Hour
                dt.hour = getHour(timestamp);

                // Minute
                dt.minute = getMinute(timestamp);

                // Second
                dt.second = getSecond(timestamp);

                // Day of week.
                dt.weekday = getWeekday(timestamp);
        }

        function getYear(uint timestamp) public pure returns (uint16) {
                uint secondsAccountedFor = 0;
                uint16 year;
                uint numLeapYears;

                // Year
                year = uint16(ORIGIN_YEAR + timestamp / YEAR_IN_SECONDS);
                numLeapYears = leapYearsBefore(year) - leapYearsBefore(ORIGIN_YEAR);

                secondsAccountedFor += LEAP_YEAR_IN_SECONDS * numLeapYears;
                secondsAccountedFor += YEAR_IN_SECONDS * (year - ORIGIN_YEAR - numLeapYears);

                while (secondsAccountedFor > timestamp) {
                        if (isLeapYear(uint16(year - 1))) {
                                secondsAccountedFor -= LEAP_YEAR_IN_SECONDS;
                        }
                        else {
                                secondsAccountedFor -= YEAR_IN_SECONDS;
                        }
                        year -= 1;
                }
                return year;
        }

        function getMonth(uint timestamp) public pure returns (uint8) {
                return parseTimestamp(timestamp).month;
        }

        function getDay(uint timestamp) public pure returns (uint8) {
                return parseTimestamp(timestamp).day;
        }

        function getHour(uint timestamp) public pure returns (uint8) {
                return uint8((timestamp / 60 / 60) % 24);
        }

        function getMinute(uint timestamp) public pure returns (uint8) {
                return uint8((timestamp / 60) % 60);
        }

        function getSecond(uint timestamp) public pure returns (uint8) {
                return uint8(timestamp % 60);
        }

        function getWeekday(uint timestamp) public pure returns (uint8) {
                return uint8((timestamp / DAY_IN_SECONDS + 4) % 7);
        }

        function toTimestamp(uint16 year, uint8 month, uint8 day) public pure returns (uint timestamp) {
                return toTimestamp(year, month, day, 0, 0, 0);
        }

        function toTimestamp(uint16 year, uint8 month, uint8 day, uint8 hour) public pure returns (uint timestamp) {
                return toTimestamp(year, month, day, hour, 0, 0);
        }

        function toTimestamp(uint16 year, uint8 month, uint8 day, uint8 hour, uint8 minute) public pure returns (uint timestamp) {
                return toTimestamp(year, month, day, hour, minute, 0);
        }

        function toTimestamp(uint16 year, uint8 month, uint8 day, uint8 hour, uint8 minute, uint8 second) public pure returns (uint timestamp) {
                uint16 i;

                // Year
                for (i = ORIGIN_YEAR; i < year; i++) {
                        if (isLeapYear(i)) {
                                timestamp += LEAP_YEAR_IN_SECONDS;
                        }
                        else {
                                timestamp += YEAR_IN_SECONDS;
                        }
                }

                // Month
                uint8[12] memory monthDayCounts;
                monthDayCounts[0] = 31;
                if (isLeapYear(year)) {
                        monthDayCounts[1] = 29;
                }
                else {
                        monthDayCounts[1] = 28;
                }
                monthDayCounts[2] = 31;
                monthDayCounts[3] = 30;
                monthDayCounts[4] = 31;
                monthDayCounts[5] = 30;
                monthDayCounts[6] = 31;
                monthDayCounts[7] = 31;
                monthDayCounts[8] = 30;
                monthDayCounts[9] = 31;
                monthDayCounts[10] = 30;
                monthDayCounts[11] = 31;

                for (i = 1; i < month; i++) {
                        timestamp += DAY_IN_SECONDS * monthDayCounts[i - 1];
                }

                // Day
                timestamp += DAY_IN_SECONDS * (day - 1);

                // Hour
                timestamp += HOUR_IN_SECONDS * (hour);

                // Minute
                timestamp += MINUTE_IN_SECONDS * (minute);

                // Second
                timestamp += second;

                return timestamp;
        }
}


