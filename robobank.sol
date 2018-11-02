pragma solidity >=0.4.24 <0.6.0;
 
import "github.com/Arachnid/solidity-stringutils/strings.sol";
import "http://github.com/OpenZeppelin/openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract RoboBank is ERC20 {
    using strings for *;
    
    event Test(string);
    event TestData(string, bool, uint, uint);
    event DealEvent(int typeEvent, address client, uint value, uint startDate, uint endDate); 
    event DealEndEvent(int typeEvent, address client, uint value, uint endDate);
    
    struct DayEntry {
        uint sum;
        uint percent;
        mapping(uint8 => HourEntry) childs;
    }
    
    struct HourEntry {
        uint sum;
        mapping(uint8 => MinuteEntry) childs;
        uint8 headIndex;
        uint8 tailIndex;
        uint8 firstHaveMoneyIndex;
    }
    
    struct MinuteEntry {
        uint sum;
        mapping(uint => Operation) operations;
        uint count;
        uint8 nextIndex;
        uint8 prevIndex;
        uint8 nextHaveMoneyIndex;
    }
    
    struct Operation {
        uint startTime;
        uint endTime;
        uint sum;
        uint percent;
        address clientAddress;
    }
    
    struct Allocate {
        uint8 hour;
        uint8 firstIndex;   // для первой структуры - первая минута слево от периода, для других первая минута часа
        uint8 lastIndex;    // если != fakeIndex, то индекс минуты у которой отщипываем сумму
        uint sum;           // сумма часа
        bool isCompleted;   // распределение закончено в этом часе?
    }
    
    struct WhiteClient {
        address clientAddress;
        uint rating; // рейтинг
        uint usedRating; // выбранный рейтинг
    }
    
    struct BlackClient {
        address clientAddress;
        CreditOperation[] credits;
    }
    
    struct Credit {
        address creditor;
        uint amount;
    }
    
    struct Credits {
        uint amount;
        uint credPercent;
        mapping (uint256 => Credit[]) creditsByTime; 
        mapping (address => CreditorList) creditsByAddress;
    }
    
    struct CreditorList {
        uint head;
        uint count;
        mapping (uint => Node) listCr;
    }
    
    struct Node {
        uint next;
        uint prev;
        uint endTime;
	uint id;
    }
    
    struct CreditOperation {
        uint256 time;
        uint amount;
    }
    
    DayEntry private deposits;
    Credits private credits;
    
    address private owner;
    uint _capital;
    uint8 _percentDeposit;
    uint8 _percentCredit;
    uint _minutePriceForDeposit;
    uint _minutePriceForCredit;
    uint8 _creditLossPercent;
    uint8 _depCredIndexInPercent;
    
    uint8 fakeIndex = 60;
    
    uint initialSupply = 10000000000000000000;
    
    mapping(address => WhiteClient) private whiteList;
    mapping(address => CreditOperation[]) private blackList;
    
    address[] whiteListKeys;
    address[] blackListKeys;
    
    mapping(uint8 => Allocate) allocates;
    
    constructor () public {
        owner = msg.sender;
        deposits = DayEntry(0, 0);
        
        _percentDeposit = 5;
    	_percentCredit = 10;
    	_creditLossPercent = 3;
    	_depCredIndexInPercent = 90;
        
        uint16 year = DateTime.getYear(now);
    	bool isLeapYear = DateTime.isLeapYear(year);
    	uint minuteInYear;
    	if (isLeapYear) {
    		minuteInYear = 366*24*60;
    	} else {
    		minuteInYear = 365*24*60;
    	}
    	_minutePriceForDeposit = _percentDeposit * 1e10 / minuteInYear;
    	_minutePriceForCredit = _percentCredit * 1e10 / minuteInYear;
        
        // создаем сразу HourEntry, т.к. это прообраз месяца, а раз в месяц депозит точно будет принят
        uint8 i;
        for (i = 0; i < 24; i++) {
            deposits.childs[i] = HourEntry(0, fakeIndex, fakeIndex, fakeIndex);
        }
        
        _capital = initialSupply - 2000000000000000000;
        _mint(owner, _capital);
        _mint(0x4b0897b0513fdc7c541b6d9d7e929c4e5364d2db, 1000000000000000000);
        _mint(0x583031d1113ad414f02576bd6afabfb302140225, 1000000000000000000);
    }
    
    modifier onlyOwner
    {
        require(
            msg.sender == owner,
            "Операция доступна только владельцу контракта!"
        );
        _;
    }
    
    function putDeposit(uint _period, uint _value) public {
    // function putDeposit(uint _period, uint _value) public payable {
        string memory result;
        uint8 haveMoneyIndex;
        uint8 nextHaveMoneyIndex;
        uint startTime = now;
        uint period = _period;
        uint value = _value;
        uint percent = calculatePercent(2, period, value);
        
        Operation memory operation = Operation(startTime, 
                                        startTime + (period * 60), 
                                        value, 
                                        percent,
                                        msg.sender);
        
        require(operation.sum != 0, 
            "Депозит не может быть принят, где деньги сынок?!"
        );
        
        require(canBeDepositPut(operation.sum), 
            "Депозит не может быть принят, пора снижать ставку!"
        );
        
        uint8 hour = DateTime.getHour(operation.endTime);
        uint8 minute = DateTime.getMinute(operation.endTime);
        
        TestData("time",false,hour,minute);
        TestData("operation",false,operation.sum,operation.percent);
        
        // увеличим сумму дня и % дня
        deposits.sum = deposits.sum + operation.sum;
        deposits.percent = deposits.percent + operation.percent;
        
        // увеличим сумму часа
        deposits.childs[hour].sum = deposits.childs[hour].sum + operation.sum; 
        
        HourEntry hourEntry = deposits.childs[hour];
        
        if (hourEntry.headIndex == fakeIndex) {
            result = "список пуст, вставим первую минуту";
            hourEntry.childs[minute] = MinuteEntry(operation.sum, 1, fakeIndex, fakeIndex, fakeIndex);
            hourEntry.headIndex = minute;
            hourEntry.tailIndex = minute;
            hourEntry.firstHaveMoneyIndex = minute;
        } else if (hourEntry.headIndex > minute) {
            result = "вставляем минуту в начало списка";
            hourEntry.childs[minute] = MinuteEntry(operation.sum, 1, hourEntry.headIndex, fakeIndex, hourEntry.firstHaveMoneyIndex);
            hourEntry.headIndex = minute;
            hourEntry.firstHaveMoneyIndex = minute;
        } else if (hourEntry.tailIndex < minute) {
            result = "вставляем минуту в конец списка";
            hourEntry.childs[minute] = MinuteEntry(operation.sum, 1, fakeIndex, hourEntry.tailIndex, fakeIndex);
            
            if (hourEntry.firstHaveMoneyIndex == fakeIndex) { 
                result = concate(result, ", выставим флаг firstHaveMoneyIndex = minute, если ранее все уже покрыты кредитами");
                hourEntry.firstHaveMoneyIndex = minute;    
                hourEntry.childs[hourEntry.tailIndex].nextIndex = minute;
                hourEntry.tailIndex = minute;
            } else if (hourEntry.childs[hourEntry.tailIndex].sum > 0) { 
                result = concate(result, " - последний шаг имеет деньги, теперь он предполедний");
                hourEntry.childs[hourEntry.tailIndex].nextHaveMoneyIndex = minute;
                hourEntry.childs[hourEntry.tailIndex].nextIndex = minute;
                hourEntry.tailIndex = minute;
            } else {
                result = concate(result, " - нужно найти минуту слева с деньгами и переписать nextHaveMoneyIndex на вставленную минуту");
                haveMoneyIndex = hourEntry.firstHaveMoneyIndex;
                nextHaveMoneyIndex = hourEntry.childs[index].nextHaveMoneyIndex;
                
                while (haveMoneyIndex < minute && nextHaveMoneyIndex < minute) {
                    haveMoneyIndex = nextHaveMoneyIndex;
                    nextHaveMoneyIndex = hourEntry.childs[haveMoneyIndex].nextHaveMoneyIndex;
                }
                
                hourEntry.childs[haveMoneyIndex].nextHaveMoneyIndex = minute;
            }
        } else {
            if (hourEntry.childs[minute].nextIndex == 0) {
                result = "создаем минуту";
                uint8 index = hourEntry.headIndex;
                uint8 nextIndex = hourEntry.childs[index].nextIndex;
                
                while (index < minute && nextIndex < minute) {
                    index = nextIndex;
                    nextIndex = hourEntry.childs[index].nextIndex;
                }
                
                hourEntry.childs[minute] = MinuteEntry(operation.sum, 1, nextIndex, index, fakeIndex);
            } else {
                result = "добавим сумму и кол-во операций в найденную минуту";
                hourEntry.childs[minute].count = hourEntry.childs[minute].count + 1; 
                hourEntry.childs[minute].sum = hourEntry.childs[minute].sum + operation.sum; 
            }
            
            if (hourEntry.firstHaveMoneyIndex > minute) {
                result = concate(result, " - устанавливаем индекс наличия денег");
                if (hourEntry.firstHaveMoneyIndex == fakeIndex) {
                    hourEntry.childs[minute].nextHaveMoneyIndex = fakeIndex;
                } else {
                    hourEntry.childs[minute].nextHaveMoneyIndex = hourEntry.firstHaveMoneyIndex;  
                }
                
                hourEntry.firstHaveMoneyIndex == minute;    
            } else {
                result = concate(result, " - бежим по минутам с деньгами от hourEntry.firstHaveMoneyIndex до minute и ищем минимально меньшую чтобы переписать ей индекс на вставленую минуту");
                haveMoneyIndex = hourEntry.firstHaveMoneyIndex;
                nextHaveMoneyIndex = hourEntry.childs[index].nextHaveMoneyIndex;
                
                while (haveMoneyIndex < minute && nextHaveMoneyIndex < minute) {
                    haveMoneyIndex = nextHaveMoneyIndex;
                    nextHaveMoneyIndex = hourEntry.childs[haveMoneyIndex].nextHaveMoneyIndex;
                }
                
                hourEntry.childs[haveMoneyIndex].nextHaveMoneyIndex = minute;
                hourEntry.childs[minute].nextHaveMoneyIndex = nextHaveMoneyIndex;
            }
        }
        
        result = concate(result, " - вставить операцию в минуту");
        
        MinuteEntry minuteEntry = hourEntry.childs[minute];
        minuteEntry.operations[minuteEntry.count-1] = operation;
        
        transfer(owner, value);
        
        emit DealEvent(2, msg.sender, operation.sum, operation.startTime, operation.endTime);
        
        TestData(string(result), false, hour, minute);
    }
    
    function returnDeposits(uint8 day, uint8 hour, uint8 minute) public payable {
        string memory result;
        
        if (deposits.childs[hour].headIndex == fakeIndex) {
            result = "hour not found";
        } else {
            HourEntry hourEntry = deposits.childs[hour];
            result = "hour found";
            
            if (hourEntry.childs[minute].nextIndex == 0) {
                result = concate(result, ", minute not found");
            } else {
                MinuteEntry minuteEntry = hourEntry.childs[minute];
                result = concate(result, ", minute found");
                
                for (uint i=0; i<minuteEntry.count; i++) {
                    TestData("returnDeposits",false,minuteEntry.operations[i].sum,minuteEntry.operations[i].percent);
                    transfer(minuteEntry.operations[i].clientAddress, minuteEntry.operations[i].sum + minuteEntry.operations[i].percent);
                    
                    deposits.percent = deposits.percent - minuteEntry.operations[i].percent;
                    _capital = _capital - minuteEntry.operations[i].percent;
                }
                
                result = concate(result, ", deposits returned");
                
                if (hourEntry.headIndex == minute) {
                    hourEntry.headIndex = minuteEntry.nextIndex;
                } else if (hourEntry.tailIndex == minute) {
                    hourEntry.tailIndex = minuteEntry.prevIndex;
                }
                
                if (hourEntry.firstHaveMoneyIndex == minute) {
                    hourEntry.firstHaveMoneyIndex = minuteEntry.nextHaveMoneyIndex;
                }
                
                delete hourEntry.childs[minute];
            }
        }
        
        Test(string(result));
    }
    
    function allocationCreditSum(uint endCreditDate, uint sumCredit) internal returns (bool) {
        string memory result;
        
        uint8 hour = DateTime.getHour(endCreditDate);
        uint8 minute = DateTime.getMinute(endCreditDate);
        
        uint sumAllocate = sumCredit;
        uint8 count = 0;
        
        while (sumAllocate > 0 && hour < 24) {
            Allocate memory alloc = getAllocationStruct(hour, minute, sumAllocate);
            allocates[count] = alloc;
            
            if (alloc.isCompleted) {
                // размещение выполнено полностью
                sumAllocate = 0;
            } else {
                // размещение выполнено не полностью, нужно смотреть следующий час
                sumAllocate = sumAllocate - alloc.sum;
                hour = hour + 1;
                minute = 0;
                count = count + 1;
            }
        }
        
        if (sumAllocate == 0) {
            // распределение удалось, проводим реальное распределение
            for (uint8 i=count; i> 0; i--) {
                allocationHour(allocates[i-1]);
                delete allocates[i-1];
            }
            
            return true;
        } else {
            // распределение не удалось
            return false;
        }
    }
    
    // посчитай покрытие с часа hourEntry c минуты withMinute для суммы sum
    function getAllocationStruct(uint8 hour, uint withMinute, uint sum) internal returns (Allocate) {
        uint8 firstIndex;
        uint8 lastIndex;
        uint8 beginIndex;
        uint8 endIndex;
        uint8 index;
        uint8 nextIndex;
        
        HourEntry hourEntry = deposits.childs[hour];
        
        if (hourEntry.firstHaveMoneyIndex > withMinute) {
            firstIndex = fakeIndex;
            beginIndex = hourEntry.firstHaveMoneyIndex;
        } else {
            // ищем минуту с деньгами сразу до withMinute
            index = hourEntry.firstHaveMoneyIndex;
            nextIndex = hourEntry.childs[index].nextHaveMoneyIndex;
            
            while (index < withMinute && nextIndex < withMinute) {
                index = nextIndex;
                nextIndex = hourEntry.childs[index].nextHaveMoneyIndex;
            }
            
            firstIndex = index;
            beginIndex = nextIndex;
        }
        
        if (firstIndex != fakeIndex && beginIndex == fakeIndex) {
            return Allocate(fakeIndex, fakeIndex, fakeIndex, 0, false);    
        } else {
            uint sumDeposits = sum;
            index = beginIndex;
            
            while (index != fakeIndex && sumDeposits != 0) {
                if (sumDeposits < hourEntry.childs[index].sum) {
                    sumDeposits = 0;
                    lastIndex = hourEntry.childs[index].nextHaveMoneyIndex;
                } else {
                    sumDeposits = sumDeposits - hourEntry.childs[index].sum; 
                    index = hourEntry.childs[index].nextHaveMoneyIndex;
                }
            }
            
            if (sumDeposits == 0) {
                // распределились в этом часу полностью
                return Allocate(hour, firstIndex, lastIndex, sum, true);
            } else {
                // распределились в этом часу частично
                return Allocate(hour, firstIndex, fakeIndex, sumDeposits, false);
            }
        }
    }
    
    // размести с часа c минуты withMinute сумму sumCredit
    function allocationHour(Allocate allocate) internal {
        uint8 firstIndex;
        uint8 index;
        uint8 nextIndex;
        
        HourEntry hourEntry = deposits.childs[allocate.hour];
        uint sum;
        
        if (allocate.firstIndex == fakeIndex) {
            // размещаем сначала и до конца или allocate.lastIndex
            index = hourEntry.firstHaveMoneyIndex;
        } else {
            // от и до конца или allocate.lastIndex
            index = hourEntry.childs[allocate.firstIndex].nextHaveMoneyIndex;
        }
        
        if (allocate.isCompleted) {
            // часть до allocate.lastIndex
            while (index != allocate.lastIndex) {
                sum = sum + hourEntry.childs[index].sum;
                hourEntry.childs[index].sum = 0;
                index = hourEntry.childs[index].nextHaveMoneyIndex;
            }
            
            hourEntry.childs[index].sum = hourEntry.childs[index].sum - (allocate.sum - sum);
            hourEntry.sum = hourEntry.sum - allocate.sum;
        } else {
            // весь период
            while (index != fakeIndex) {
                hourEntry.childs[index].sum = 0;
                index = hourEntry.childs[index].nextHaveMoneyIndex;
            }
            
            if (allocate.firstIndex == fakeIndex) {
                hourEntry.sum = 0;
            } else {
                hourEntry.sum = hourEntry.sum - allocate.sum;
            }
        }
    }
    
    function allocationCreditSumTest(uint endCreditDate, uint sumCredit) public payable returns (bool) {
        return allocationCreditSum(endCreditDate, sumCredit);
    }
    
    // рассылка депозитов и проверка дефолтов по кредитам    
    // typeEvent = 0 - кредит и депозит, 1 - кредит, 2 - депозит
    function watchDog(uint8 typeEvent, uint timestamp) public payable {
        require(msg.sender == owner);
        
        if (typeEvent == 1 || typeEvent == 0) {
            checkCredits(timestamp / 60);
        }
        
        if (typeEvent == 2 || typeEvent == 0) {
            returnDeposits(2, DateTime.getHour(timestamp), DateTime.getMinute(timestamp));
        }
    }
    
    // установка значений процентов
    function setSettings(uint8 percentDeposit, uint8 percentCredit) public payable {
        require(msg.sender == owner);
        require(percentDeposit < percentCredit, "Процент по депозиту должен быть меньше процента по кредиту");
        
        _percentDeposit = percentCredit;
        _percentCredit = percentCredit;
    }
    
       event CreditHasTaken(uint256 t);
    
    function getCredit(uint256 duration, uint16 amount) public payable {
        address to = msg.sender;
          //check black list
          require (
              blackList[to].length == 0,
              "Вы в черном списке"
          );
          
          //check rating
          uint256 need = duration * amount;
          uint256 have = 0;
          
          WhiteClient memory client = whiteList[to];
          if (client.clientAddress == 0) {
              have = 1;
          } else {
              have = client.rating - client.usedRating;
          }
              
          require (
              need <= have,
              "У Вас нет рейтинга"
          );
          
          // check coverage
        //   require(
        //       allocationCreditSum(endTime * 60, amount),
        //       "Нет покрытия"
        //   );
          
          // all checks are successful    
        //   updateRatings(to, need, 1);//TODO 
          
          Credits storage allCredits = credits;
          Credit memory credit = Credit(to, amount);
          uint256 endTime = now / 60 + duration;
          credits.creditsByTime[endTime].push(credit);
          add(credits.creditsByAddress[to], endTime, credits.creditsByTime[endTime].length - 1);
          credits.amount += amount;
          credits.credPercent += amount * _percentCredit;
          to.transfer(amount); //TODO    
        emit CreditHasTaken(endTime);     
    }
    
    event SuccessfulRepayment(string, uint);
    
    function earlyRepayment(uint amount) public payable {
        address repayer = msg.sender;
        
        //add BL
        Credits storage allCreds = credits;
        CreditorList storage list = allCreds.creditsByAddress[repayer];
        bool next = true;
        uint head = list.head;
        while (next) {
            if (head == 0) {
                list.count = 0;
                next = false;
            } else {
                Node storage n = list.listCr[head];
                Credit[] storage creds = allCreds.creditsByTime[n.endTime];
                Credit storage cred = creds[n.id];
                if (amount > cred.amount) {
                    amount -= cred.amount;
                    delete creds[n.id];
                    list.head = list.listCr[head].next;
                    head = list.head;
                } else {
                    if (amount == cred.amount) {
                        delete creds[n.id];
                        list.head = list.listCr[head].next;
                        head = list.head;
                    } else {
                        cred.amount -=amount;
                    }
                    next = false;
                    amount = 0;
                }  
            }
        }
        
        if (amount > 0) {
           repayer.transfer(amount);  
        }
       
        // allCreds.amount -= amount;
        // allCreds.credPercent -= amount * _percentCredit;
        // updateRatings(repayer, amount, 1);
        emit SuccessfulRepayment("Кредит погашен", amount);
    }
    
    function add(CreditorList storage list, uint endTime, uint id) private returns (bool) {
        list.count++;
        if (list.head == 0) {
          list.head = list.count;
          Node memory n = Node(0, 0, endTime, id);
          list.listCr[list.count] = n;
        } else {
            bool next = true;
            Node memory newNode;
            Node storage condidat = list.listCr[list.head];
            uint condidatInd = list.head;
            while (next) {
                if (condidat.endTime < endTime) {
                    
                    if (condidat.next == 0) {
                        condidat.next = list.count;
                        newNode = Node(0, condidatInd, endTime, id);
                        list.listCr[list.count] = newNode;
                        next = false;
                    } else {
                        condidatInd = condidat.next;
                        condidat = list.listCr[condidat.next];
                    }
                } else {
                    if (condidat.prev == 0) {
                        list.head = list.count;
                        newNode = Node(condidatInd, 0, endTime, id);
                    } else {
                        newNode = Node(condidatInd, condidat.prev, endTime, id);
                        list.listCr[condidat.prev].next = list.count;
                        condidat.prev = list.count;
                    }
                    list.listCr[list.count] = newNode;
                    next = false;
                }
            }
        }
    }
    
    function getWhiteList() public view returns (string) {
        string memory result = "[";
        require(msg.sender == owner);
        for (uint i = 0; i < whiteListKeys.length; i++) {
            if (i != 0) {
                result = concate(result, ",");
            }
            address currentAddress = whiteListKeys[i];
            WhiteClient currentWhiteClient = whiteList[currentAddress];
            result = concate(result, concate(concate(concate("{address:",address2str(currentAddress)),getWhiteClient(currentWhiteClient)),"}"));
        }
        result = concate(result, "]");
        return result;
    }
    
    function getWhiteClient(WhiteClient whiteClient) internal returns (string) {
        string memory result;
        return concate(concate(",rating:", uint2str(whiteClient.rating)), concate(",usedRating:", uint2str(whiteClient.usedRating)));
    }
    
    function kill() public {
        require(msg.sender == owner);
        selfdestruct(msg.sender);
    }
    
    // увеличь рейтинг и уменьши выбранный рейтинг 
    function updateRatings(address clientAddress, uint usedRating, uint creditNumber) internal {
        WhiteClient whiteClient = whiteList[clientAddress];
        whiteClient.usedRating += usedRating;
        uint currentRating = whiteClient.rating;
        whiteClient.rating *= usedRating/currentRating * _creditLossPercent * (1 + 1 / creditNumber) / 10;
    }
    
    function checkCredits(uint time) internal {
        Credit[] memory creditsAtTime = credits.creditsByTime[time];
        for (uint16 i = 0; i < creditsAtTime.length; i++) {
             Credit memory blackCredit = creditsAtTime[i];
			 address blackAddress = blackCredit.creditor;
			 CreditOperation[] storage blackOperationsForClient = blackList[blackAddress];
			 blackOperationsForClient.push(CreditOperation(time, blackCredit.amount));
        }
    }
    
    // Проверяем, можем ли дать новый депозит
    function canBeDepositPut(uint depositSum) internal returns (bool) {
        uint creditLoss = credits.amount*_creditLossPercent / 100;
        uint totalLoss = deposits.percent + creditLoss;
        uint totalEarnPlusCapital = credits.credPercent + _capital;
        return totalLoss < totalEarnPlusCapital * _depCredIndexInPercent / 100;
    }
    
    function calculatePercent(uint8 typeEvent, uint period, uint sum) internal returns (uint) {
        if (typeEvent == 1) {
	        return (sum * period * _minutePriceForDeposit) / 1e12;
        } else if (typeEvent == 2) {
	        return (sum * period * _minutePriceForCredit) / 1e12;
        } else {
            return 0;
        }
    }
    
    function address2str(address x) returns (string) {
        bytes memory b = new bytes(20);
        for (uint i = 0; i < 20; i++)
            b[i] = byte(uint8(uint(x) / (2**(8*(19 - i)))));
        return string(b);
    }
    
    function concate(string memory s1, string memory s2) internal returns (string) {
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
}

library DateTime {
    uint constant YEAR_IN_SECONDS = 31536000;
    uint constant LEAP_YEAR_IN_SECONDS = 31622400;

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

    function getHour(uint timestamp) public pure returns (uint8) {
            return uint8((timestamp / 60 / 60) % 24);
    }

    function getMinute(uint timestamp) public pure returns (uint8) {
            return uint8((timestamp / 60) % 60);
    }
}
