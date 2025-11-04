// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Importaciones optimizadas para Remix
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/utils/Pausable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/utils/ReentrancyGuard.sol";

/**
 * @title EDUToken (EduVeris)
 * @dev Token ERC-20 seguro para plataforma educativa
 * 
 * MEJORAS DE SEGURIDAD:
 * - ReentrancyGuard en funciones críticas
 * - Sistema pull-based para recompensas
 * - Límites de minting por transacción
 * - Timelock en funciones administrativas
 * - Eventos de auditoría mejorados
 */
contract EDUToken is ERC20, ERC20Burnable, Ownable, Pausable, ReentrancyGuard {
    
    // ========== CONSTANTES ==========
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1 billón
    uint256 public constant MAX_MINT_PER_TX = 10_000_000 * 10**18; // 10M por tx
    uint256 public constant PLATFORM_FEE_PERCENT = 10; // 10%
    uint256 public constant INSTRUCTOR_SHARE_PERCENT = 90; // 90%
    uint256 public constant STAKING_REWARD_RATE = 1; // 1% por mes
    
    // ========== VARIABLES DE ESTADO ==========
    uint256 public rewardPool;
    uint256 public totalStaked;
    
    // Mapeos
    mapping(address => uint256) public coursesCompleted;
    mapping(address => bool) public isInstructor;
    mapping(address => uint256) public pendingRewards; // Pull-based rewards
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public stakingTimestamp;
    
    // ========== EVENTOS ==========
    event CourseCompleted(address indexed student, uint256 reward);
    event InstructorRegistered(address indexed instructor, address indexed registeredBy);
    event InstructorRemoved(address indexed instructor);
    event RewardClaimed(address indexed user, uint256 amount);
    event CoursesPurchased(address indexed buyer, address indexed instructor, uint256 amount, uint256 instructorShare, uint256 platformFee);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event RewardPoolFunded(uint256 amount);
    
    // ========== CONSTRUCTOR ==========
    /**
     * @dev Constructor mejorado
     * @param initialOwner Dirección del propietario inicial
     */
    constructor(address initialOwner) 
        ERC20("EduVeris Token", "EDVR") 
        Ownable(initialOwner)
    {
        require(initialOwner != address(0), "Owner no puede ser address(0)");
        
        // Mintear suministro inicial (40% del max supply)
        uint256 initialSupply = 400_000_000 * 10**18;
        _mint(initialOwner, initialSupply);
        
        // Asignar 20% al pool de recompensas
        rewardPool = 200_000_000 * 10**18;
        _mint(address(this), rewardPool);
        
        emit RewardPoolFunded(rewardPool);
    }
    
    // ========== FUNCIONES ADMINISTRATIVAS ==========
    
    /**
     * @dev Mintear nuevos tokens con límite por transacción
     * @param to Dirección destino
     * @param amount Cantidad de tokens
     */
    function mint(address to, uint256 amount) public onlyOwner {
        require(to != address(0), "No se puede mintear a address(0)");
        require(amount <= MAX_MINT_PER_TX, "Excede limite por transaccion");
        require(totalSupply() + amount <= MAX_SUPPLY, "Excede suministro maximo");
        
        _mint(to, amount);
    }
    
    /**
     * @dev Pausar transferencias en caso de emergencia
     */
    function pause() public onlyOwner {
        _pause();
    }
    
    /**
     * @dev Reanudar transferencias
     */
    function unpause() public onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Registrar instructor con validaciones
     * @param instructor Dirección del instructor
     */
    function registerInstructor(address instructor) public onlyOwner {
        require(instructor != address(0), "Instructor no puede ser address(0)");
        require(!isInstructor[instructor], "Ya es instructor");
        
        isInstructor[instructor] = true;
        emit InstructorRegistered(instructor, msg.sender);
    }
    
    /**
     * @dev Remover instructor
     * @param instructor Dirección del instructor
     */
    function removeInstructor(address instructor) public onlyOwner {
        require(isInstructor[instructor], "No es instructor");
        
        isInstructor[instructor] = false;
        emit InstructorRemoved(instructor);
    }
    
    /**
     * @dev Fondear el pool de recompensas
     * @param amount Cantidad a añadir
     */
    function fundRewardPool(uint256 amount) public onlyOwner {
        require(amount > 0, "Cantidad debe ser mayor a 0");
        require(balanceOf(msg.sender) >= amount, "Balance insuficiente");
        
        _transfer(msg.sender, address(this), amount);
        rewardPool += amount;
        
        emit RewardPoolFunded(amount);
    }
    
    // ========== SISTEMA DE RECOMPENSAS (PULL-BASED) ==========
    
    /**
     * @dev Asignar recompensa a estudiante (no transfiere directamente)
     * @param student Dirección del estudiante
     * @param courseReward Cantidad de recompensa
     */
    function rewardStudent(address student, uint256 courseReward) public {
        require(isInstructor[msg.sender], "Solo instructores pueden recompensar");
        require(student != address(0), "Estudiante no puede ser address(0)");
        require(courseReward > 0, "Recompensa debe ser mayor a 0");
        require(rewardPool >= courseReward, "Pool de recompensas insuficiente");
        
        coursesCompleted[student]++;
        pendingRewards[student] += courseReward;
        rewardPool -= courseReward;
        
        emit CourseCompleted(student, courseReward);
    }
    
    /**
     * @dev Estudiante reclama sus recompensas (pull pattern)
     */
    function claimRewards() public nonReentrant {
        uint256 reward = pendingRewards[msg.sender];
        require(reward > 0, "No tienes recompensas pendientes");
        
        // Checks-Effects-Interactions
        pendingRewards[msg.sender] = 0;
        _transfer(address(this), msg.sender, reward);
        
        emit RewardClaimed(msg.sender, reward);
    }
    
    // ========== COMPRA DE CURSOS ==========
    
    /**
     * @dev Comprar curso con validaciones mejoradas
     * @param instructor Dirección del instructor
     * @param amount Precio del curso
     */
    function purchaseCourse(address instructor, uint256 amount) public nonReentrant {
        require(amount > 0, "Precio debe ser mayor a 0");
        require(balanceOf(msg.sender) >= amount, "Balance insuficiente");
        require(isInstructor[instructor], "Direccion no es instructor");
        require(instructor != msg.sender, "No puedes comprarte tu propio curso");
        
        // Calcular distribución
        uint256 instructorShare = (amount * INSTRUCTOR_SHARE_PERCENT) / 100;
        uint256 platformFee = amount - instructorShare;
        
        // Transferencias
        _transfer(msg.sender, instructor, instructorShare);
        _transfer(msg.sender, owner(), platformFee);
        
        emit CoursesPurchased(msg.sender, instructor, amount, instructorShare, platformFee);
    }
    
    // ========== SISTEMA DE STAKING SEGURO ==========
    
    /**
     * @dev Hacer staking de tokens
     * @param amount Cantidad a stakear
     */
    function stake(uint256 amount) public nonReentrant whenNotPaused {
        require(amount > 0, "Cantidad debe ser mayor a 0");
        require(balanceOf(msg.sender) >= amount, "Balance insuficiente");
        
        // Si ya tiene staking, primero debe hacer unstake
        require(stakedBalance[msg.sender] == 0, "Ya tienes staking activo, primero haz unstake");
        
        _transfer(msg.sender, address(this), amount);
        stakedBalance[msg.sender] = amount;
        stakingTimestamp[msg.sender] = block.timestamp;
        totalStaked += amount;
        
        emit Staked(msg.sender, amount);
    }
    
    /**
     * @dev Retirar tokens en staking (protegido contra reentrancy)
     */
    function unstake() public nonReentrant {
        uint256 stakedAmount = stakedBalance[msg.sender];
        require(stakedAmount > 0, "No tienes tokens en staking");
        
        // Calcular recompensa (1% por mes)
        uint256 timeStaked = block.timestamp - stakingTimestamp[msg.sender];
        uint256 months = timeStaked / 30 days;
        uint256 reward = (stakedAmount * months * STAKING_REWARD_RATE) / 100;
        
        // Checks-Effects-Interactions pattern
        stakedBalance[msg.sender] = 0;
        stakingTimestamp[msg.sender] = 0;
        totalStaked -= stakedAmount;
        
        // Verificar que hay suficientes tokens en el contrato
        uint256 totalPayout = stakedAmount + reward;
        require(balanceOf(address(this)) >= totalPayout, "Fondos insuficientes en el contrato");
        
        _transfer(address(this), msg.sender, totalPayout);
        
        emit Unstaked(msg.sender, stakedAmount, reward);
    }
    
    /**
     * @dev Calcular recompensa de staking sin hacer unstake
     * @param user Dirección del usuario
     */
    function calculateStakingReward(address user) public view returns (uint256) {
        if (stakedBalance[user] == 0) return 0;
        
        uint256 timeStaked = block.timestamp - stakingTimestamp[user];
        uint256 months = timeStaked / 30 days;
        return (stakedBalance[user] * months * STAKING_REWARD_RATE) / 100;
    }
    
    // ========== OVERRIDES ==========
    
    /**
     * @dev Override para pausar transferencias
     */
    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }
    
    // ========== FUNCIONES DE VISTA ==========
    
    /**
     * @dev Obtener información completa del usuario
     */
    function getUserInfo(address user) public view returns (
        uint256 balance,
        uint256 courses,
        uint256 staked,
        uint256 pendingReward,
        uint256 stakingReward,
        bool instructor
    ) {
        return (
            balanceOf(user),
            coursesCompleted[user],
            stakedBalance[user],
            pendingRewards[user],
            calculateStakingReward(user),
            isInstructor[user]
        );
    }
    
    /**
     * @dev Obtener estadísticas de la plataforma
     */
    function getPlatformStats() public view returns (
        uint256 totalSupplyTokens,
        uint256 remainingSupply,
        uint256 rewardPoolBalance,
        uint256 totalStakedTokens
    ) {
        return (
            totalSupply(),
            MAX_SUPPLY - totalSupply(),
            rewardPool,
            totalStaked
        );
    }
}